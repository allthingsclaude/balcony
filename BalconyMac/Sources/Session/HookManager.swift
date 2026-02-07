import Foundation
import BalconyShared
import os

// MARK: - Hook Events

/// Events received from Claude Code hooks via Unix domain socket.
public enum HookEvent: Sendable {
    case preToolUse(sessionId: String, toolName: String, input: String)
    case postToolUse(sessionId: String, toolName: String, output: String)
    case notification(sessionId: String, message: String)
    case sessionStop(sessionId: String)
}

// MARK: - HookManager

/// Manages Claude Code hooks for BalconyMac integration.
///
/// Installs shell hook scripts in `~/.claude/hooks/` that forward events
/// to BalconyMac via a Unix domain socket at `/tmp/balcony.sock`.
actor HookManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookManager")
    private let hooksDir: String
    private let socketPath: String

    private var socketServer: UnixSocketServer?
    private var continuation: AsyncStream<HookEvent>.Continuation?
    private var isListening = false

    init(
        hooksDir: String = "\(NSHomeDirectory())/.claude/hooks",
        socketPath: String = "/tmp/balcony.sock"
    ) {
        self.hooksDir = hooksDir
        self.socketPath = socketPath
    }

    // MARK: - Hook Installation

    /// Install Balcony hooks into Claude Code hooks directory.
    func installHooks() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        let hooks = ["PreToolUse", "PostToolUse", "Notification", "Stop"]
        for hookName in hooks {
            let hookPath = "\(hooksDir)/\(hookName).sh"
            if !fm.fileExists(atPath: hookPath) {
                let script = generateHookScript(name: hookName)
                try script.write(toFile: hookPath, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
                logger.info("Installed hook: \(hookName)")
            }
        }
    }

    /// Remove Balcony hooks.
    func removeHooks() throws {
        let fm = FileManager.default
        let hooks = ["PreToolUse", "PostToolUse", "Notification", "Stop"]
        for hookName in hooks {
            let hookPath = "\(hooksDir)/\(hookName).sh"
            if fm.fileExists(atPath: hookPath) {
                try fm.removeItem(atPath: hookPath)
                logger.info("Removed hook: \(hookName)")
            }
        }
    }

    // MARK: - Socket Listener

    /// Start listening for hook events and return a stream.
    func startListening() -> AsyncStream<HookEvent> {
        guard !isListening else {
            return AsyncStream { $0.finish() }
        }
        isListening = true

        let (stream, continuation) = AsyncStream.makeStream(of: HookEvent.self)
        self.continuation = continuation

        let server = UnixSocketServer(socketPath: socketPath) { [weak self] data in
            guard let self else { return }
            Task { await self.handleSocketData(data) }
        }

        if server.start() {
            self.socketServer = server
            logger.info("Listening on \(self.socketPath)")
        } else {
            logger.error("Failed to start socket server")
            continuation.finish()
        }

        return stream
    }

    /// Stop listening for hook events.
    func stopListening() {
        isListening = false
        socketServer?.stop()
        socketServer = nil
        continuation?.finish()
        continuation = nil
        logger.info("Stopped listening")
    }

    // MARK: - Event Parsing

    private func handleSocketData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hookName = json["hook"] as? String else {
            logger.warning("Failed to parse hook data")
            return
        }

        // The "data" field contains the JSON that was piped via stdin to the hook script
        let hookData = json["data"] as? [String: Any] ?? [:]
        let sessionId = hookData["session_id"] as? String ?? "unknown"

        let event: HookEvent
        switch hookName {
        case "PreToolUse":
            event = .preToolUse(
                sessionId: sessionId,
                toolName: hookData["tool"] as? String ?? "unknown",
                input: stringifyJSON(hookData["input"])
            )
        case "PostToolUse":
            event = .postToolUse(
                sessionId: sessionId,
                toolName: hookData["tool"] as? String ?? "unknown",
                output: stringifyJSON(hookData["output"])
            )
        case "Notification":
            event = .notification(
                sessionId: sessionId,
                message: hookData["message"] as? String ?? ""
            )
        case "Stop":
            event = .sessionStop(sessionId: sessionId)
        default:
            logger.warning("Unknown hook: \(hookName)")
            return
        }

        continuation?.yield(event)
        logger.debug("Hook event: \(hookName) for session \(sessionId)")
    }

    // MARK: - Helpers

    private func generateHookScript(name: String) -> String {
        """
        #!/bin/bash
        # Balcony Claude Code Hook: \(name)
        # Forwards events to BalconyMac via Unix domain socket.
        # Auto-generated by BalconyMac - do not edit manually.

        SOCKET="/tmp/balcony.sock"
        if [ -S "$SOCKET" ]; then
            echo "{\\"hook\\": \\"\(name)\\", \\"data\\": $(cat -)}" | nc -U "$SOCKET" 2>/dev/null || true
        fi
        """
    }

    /// Convert an arbitrary JSON value to a string for event payload.
    private func stringifyJSON(_ value: Any?) -> String {
        guard let value else { return "" }
        if let str = value as? String { return str }
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }
}

// MARK: - Unix Domain Socket Server

/// Listens on a Unix domain socket for incoming connections.
/// Each connection is read fully, then the data is passed to the callback.
private final class UnixSocketServer: @unchecked Sendable {
    private let socketPath: String
    private let callback: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "com.balcony.socket", qos: .utility)
    private var serverFD: Int32 = -1
    private var isRunning = false

    init(socketPath: String, callback: @escaping @Sendable (Data) -> Void) {
        self.socketPath = socketPath
        self.callback = callback
    }

    /// Start the socket server. Returns true on success.
    func start() -> Bool {
        // Remove stale socket file
        unlink(socketPath)

        // Create socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return false }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            socketPath.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            serverFD = -1
            return false
        }

        // Listen
        guard listen(serverFD, 5) == 0 else {
            close(serverFD)
            serverFD = -1
            return false
        }

        isRunning = true

        // Accept loop on dedicated queue
        queue.async { [weak self] in
            self?.acceptLoop()
        }

        return true
    }

    /// Stop the server and clean up.
    func stop() {
        isRunning = false
        if serverFD >= 0 {
            // Close the server socket to unblock accept()
            Darwin.close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else {
                // accept() returns -1 when server socket is closed during shutdown
                continue
            }

            // Read client data on a separate queue to not block accept
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        defer { Darwin.close(clientFD) }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(clientFD, buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }

        guard !data.isEmpty else { return }
        callback(data)
    }
}
