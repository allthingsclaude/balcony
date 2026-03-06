import Foundation
import BalconyShared
import os

/// Reads Claude Code session files from `~/.claude/projects/` and extracts metadata.
actor SessionFileReader {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "SessionFileReader")

    /// Maximum sessions to return (most recent by file modification date).
    private let maxSessions = 30

    /// List available sessions for a given project path.
    /// Pre-sorts by modification date and only parses the most recent files.
    func listSessions(for projectPath: String) async -> [SessionInfo] {
        let projectHash = hashProjectPath(projectPath)
        let sessionsDir = claudeProjectsPath().appendingPathComponent(projectHash)

        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            logger.warning("No sessions directory at: \(sessionsDir.path)")
            return []
        }

        // List files and get attributes in one pass
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Filter, get attributes, and sort by mod date — all before parsing content
        struct Candidate {
            let url: URL
            let sessionId: String
            let modDate: Date
            let fileSize: Int64
        }

        var candidates: [Candidate] = []
        for fileURL in files where fileURL.pathExtension == "jsonl" {
            let name = fileURL.deletingPathExtension().lastPathComponent
            if name.hasPrefix("agent-") { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modDate = values.contentModificationDate,
                  let fileSize = values.fileSize,
                  fileSize > 0 else { continue }

            candidates.append(Candidate(url: fileURL, sessionId: name, modDate: modDate, fileSize: Int64(fileSize)))
        }

        // Sort newest first and take only the top N — avoids parsing old sessions
        candidates.sort { $0.modDate > $1.modDate }
        let topCandidates = candidates.prefix(maxSessions)

        // Parse metadata from the top candidates
        var sessions: [SessionInfo] = []
        sessions.reserveCapacity(topCandidates.count)

        for c in topCandidates {
            let (title, branch) = extractSessionMetadata(from: c.url)
            guard let title else { continue }

            sessions.append(SessionInfo(
                id: c.sessionId,
                projectPath: projectPath,
                title: title,
                lastModified: c.modDate,
                fileSize: c.fileSize,
                branch: branch
            ))
        }

        logger.info("Loaded \(sessions.count) sessions for picker")
        return sessions
    }

    // MARK: - Session File Parsing

    /// Read the first few KB of a file and extract title + branch.
    /// Uses a single buffered read instead of byte-by-byte FileHandle access.
    private func extractSessionMetadata(from fileURL: URL) -> (title: String?, branch: String?) {
        // Read a small chunk from the start of the file — enough for metadata lines.
        // Most sessions have title + branch within the first 8 KB.
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return (nil, nil)
        }
        defer { try? fileHandle.close() }

        let chunkSize = 16_384 // 16 KB
        guard let chunk = try? fileHandle.read(upToCount: chunkSize),
              !chunk.isEmpty else {
            return (nil, nil)
        }

        var title: String?
        var branch: String?

        // Split chunk into lines and parse each as JSON
        chunk.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = buffer.count
            var lineStart = 0

            for i in 0..<count {
                guard base[i] == UInt8(ascii: "\n") else { continue }

                let lineLength = i - lineStart
                guard lineLength > 0 else {
                    lineStart = i + 1
                    continue
                }

                let lineData = Data(bytes: base + lineStart, count: lineLength)
                lineStart = i + 1

                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                // Extract branch (usually in first few lines)
                if branch == nil, let b = json["gitBranch"] as? String, !b.isEmpty {
                    branch = b
                }

                // Extract title from first real user message
                if title == nil,
                   let type = json["type"] as? String, type == "user",
                   let message = json["message"] as? [String: Any],
                   let content = message["content"] {
                    if let text = content as? String {
                        title = extractTitleFromText(text)
                    } else if let blocks = content as? [[String: Any]],
                              let firstBlock = blocks.first,
                              let blockType = firstBlock["type"] as? String,
                              blockType == "text",
                              let text = firstBlock["text"] as? String {
                        title = extractTitleFromText(text)
                    }
                }

                if title != nil && branch != nil { return }
            }
        }

        return (title, branch)
    }

    /// Extract a clean title from user message text (first line, max 60 chars).
    /// Returns nil for system-generated messages (e.g. `<local-command-caveat>`).
    private func extractTitleFromText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Skip system-generated messages injected by Claude Code
        if trimmed.hasPrefix("<") { return nil }

        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed

        if firstLine.count > 60 {
            let index = firstLine.index(firstLine.startIndex, offsetBy: 60)
            return String(firstLine[..<index]) + "..."
        }

        return firstLine
    }

    // MARK: - Message Counting

    /// Count user and assistant messages for a specific Claude session.
    /// Falls back to the most recently active JSONL file if no session ID is provided.
    func countMessages(projectPath: String, claudeSessionId: String? = nil) -> Int {
        let hash = hashProjectPath(projectPath)
        let dir = claudeProjectsPath().appendingPathComponent(hash)

        let url: URL
        if let sessionId = claudeSessionId {
            // Count from the specific session's JSONL file
            let fileURL = dir.appendingPathComponent("\(sessionId).jsonl")
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
            url = fileURL
        } else {
            // Fallback: find most recently modified non-agent JSONL file
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            var latestURL: URL?
            var latestDate = Date.distantPast
            for file in files where file.pathExtension == "jsonl" && !file.lastPathComponent.hasPrefix("agent-") {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   date > latestDate {
                    latestDate = date
                    latestURL = file
                }
            }

            guard let found = latestURL else { return 0 }
            url = found
        }

        guard let data = try? Data(contentsOf: url) else { return 0 }

        // Fast byte scan: count lines containing "type":"user" or "type":"assistant"
        let userTag = Array("\"type\":\"user\"".utf8)
        let assistantTag = Array("\"type\":\"assistant\"".utf8)
        var count = 0

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let total = buffer.count
            var lineStart = 0

            for i in 0...total {
                let isEnd = (i == total) || (base[i] == UInt8(ascii: "\n"))
                guard isEnd else { continue }
                let lineLen = i - lineStart
                if lineLen > 10 {
                    if scanForPattern(base + lineStart, lineLen, userTag) ||
                       scanForPattern(base + lineStart, lineLen, assistantTag) {
                        count += 1
                    }
                }
                lineStart = i + 1
            }
        }

        return count
    }

    /// Scan a byte range for a pattern (simple linear search).
    private func scanForPattern(_ base: UnsafePointer<UInt8>, _ len: Int, _ pattern: [UInt8]) -> Bool {
        let patLen = pattern.count
        guard len >= patLen else { return false }
        let limit = len - patLen
        for i in 0...limit {
            var match = true
            for j in 0..<patLen {
                if base[i + j] != pattern[j] { match = false; break }
            }
            if match { return true }
        }
        return false
    }

    // MARK: - Path Helpers

    private func claudeProjectsPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    private func hashProjectPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
    }
}
