import Foundation
import os

/// Writes input text to the TTY of a running Claude Code process,
/// matching the process by its working directory.
actor TTYWriter {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "TTYWriter")

    /// Cached CWD→TTY mapping with expiration.
    private struct CachedTTY {
        let ttyPath: String
        let expiresAt: Date
    }

    private var cache: [String: CachedTTY] = [:]
    private let cacheTTL: TimeInterval = 30

    // MARK: - Public API

    /// Write text followed by a newline to the TTY associated with the given CWD.
    func write(_ text: String, toCWD cwd: String) async throws {
        let ttyPath = try await resolveTTY(forCWD: cwd)

        let payload = text + "\n"
        guard let data = payload.data(using: .utf8) else {
            throw TTYWriterError.encodingFailed
        }

        let fd = open(ttyPath, O_WRONLY | O_NOCTTY)
        guard fd >= 0 else {
            throw TTYWriterError.openFailed(ttyPath, errno)
        }
        defer { close(fd) }

        let written = data.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress!, ptr.count)
        }

        guard written == data.count else {
            throw TTYWriterError.writeFailed(ttyPath, errno)
        }

        logger.info("Wrote \(text.prefix(50).count) chars to \(ttyPath)")
    }

    // MARK: - TTY Resolution

    private func resolveTTY(forCWD cwd: String) async throws -> String {
        // Check cache
        if let cached = cache[cwd], cached.expiresAt > Date() {
            return cached.ttyPath
        }

        // Find Claude processes and their TTYs
        let ttyPath = try findTTY(forCWD: cwd)

        // Cache result
        cache[cwd] = CachedTTY(
            ttyPath: ttyPath,
            expiresAt: Date().addingTimeInterval(cacheTTL)
        )

        return ttyPath
    }

    private func findTTY(forCWD cwd: String) throws -> String {
        // Get process list with TTYs using ps
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,tty,comm"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Find Claude Code processes (node processes running claude)
        var candidates: [(pid: pid_t, tty: String)] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }

            guard let pid = pid_t(parts[0]) else { continue }
            let tty = String(parts[1])
            let comm = String(parts[2])

            // Skip processes without a TTY
            guard tty != "??" && !tty.isEmpty else { continue }

            // Look for node processes (Claude Code runs as node)
            guard comm.contains("node") || comm.contains("claude") else { continue }

            candidates.append((pid: pid, tty: tty))
        }

        // Match by CWD using proc_pidinfo
        for candidate in candidates {
            if let processCWD = getProcessCWD(candidate.pid), processCWD == cwd {
                let ttyPath = "/dev/" + candidate.tty
                logger.info("Matched PID \(candidate.pid) TTY \(ttyPath) for CWD \(cwd)")
                return ttyPath
            }
        }

        // Fallback: try matching parent processes (Claude Code may spawn child processes)
        for candidate in candidates {
            let ppid = getParentPID(candidate.pid)
            if ppid > 0, let parentCWD = getProcessCWD(ppid), parentCWD == cwd {
                let ttyPath = "/dev/" + candidate.tty
                logger.info("Matched parent PID \(ppid) TTY \(ttyPath) for CWD \(cwd)")
                return ttyPath
            }
        }

        throw TTYWriterError.noTTYFound(cwd)
    }

    // MARK: - Process Info

    private func getProcessCWD(_ pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, Int32(size))
        guard result == size else { return nil }

        return withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cstr in
                String(cString: cstr)
            }
        }
    }

    private func getParentPID(_ pid: pid_t) -> pid_t {
        var bsdInfo = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(size))
        guard result == size else { return 0 }
        return pid_t(bsdInfo.pbi_ppid)
    }
}

// MARK: - Errors

enum TTYWriterError: LocalizedError {
    case noTTYFound(String)
    case openFailed(String, Int32)
    case writeFailed(String, Int32)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noTTYFound(let cwd):
            return "No Claude process TTY found for CWD: \(cwd)"
        case .openFailed(let path, let err):
            return "Failed to open \(path): \(String(cString: strerror(err)))"
        case .writeFailed(let path, let err):
            return "Failed to write to \(path): \(String(cString: strerror(err)))"
        case .encodingFailed:
            return "Failed to encode text as UTF-8"
        }
    }
}
