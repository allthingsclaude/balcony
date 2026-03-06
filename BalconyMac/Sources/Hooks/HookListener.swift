import Foundation
import BalconyShared
import os

/// Listens for Claude Code hook events via a Unix domain socket.
///
/// For PermissionRequest hooks (synchronous): the hook handler script sends
/// the event JSON, shuts down its write side, and waits for a response.
/// HookListener keeps the connection open and sends the decision back.
///
/// For other hooks (async): the handler sends event JSON and closes.
/// HookListener reads until EOF, parses, and closes.
actor HookListener {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookListener")

    private let socketPath: String
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    /// Serial queue for accept() calls only — never blocks.
    private let acceptQueue = DispatchQueue(label: "com.balcony.mac.hooks.accept", qos: .userInteractive)
    /// Concurrent queue for blocking read() calls — multiple connections read in parallel.
    private let readQueue = DispatchQueue(label: "com.balcony.mac.hooks.read", qos: .userInteractive, attributes: .concurrent)

    /// Open hook handler connections waiting for a response, keyed by Claude session ID.
    private var pendingResponseFDs: [String: Int32] = [:]

    /// Called when a hook event is received and parsed.
    private var onHookEvent: (@Sendable (HookEvent) -> Void)?

    /// Set the hook event callback.
    func setOnHookEvent(_ handler: @escaping @Sendable (HookEvent) -> Void) {
        onHookEvent = handler
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.socketPath = "\(home)/.balcony/hooks.sock"
    }

    // MARK: - Lifecycle

    /// Start the Unix domain socket server for hook events.
    func start() throws {
        // Ensure directory exists
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Remove stale socket file
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .ENODEV)
        }

        let flags = fcntl(serverFD, F_GETFL)
        _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(pathBytes.count)) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }

        guard bindResult == 0 else {
            close(serverFD)
            serverFD = -1
            throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE)
        }

        guard listen(serverFD, 16) == 0 else {
            close(serverFD)
            serverFD = -1
            throw POSIXError(.init(rawValue: errno) ?? .EOPNOTSUPP)
        }

        logger.info("Hook socket server listening at \(self.socketPath)")

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            Task { await self?.acceptClients() }
        }
        source.resume()
        acceptSource = source
    }

    /// Stop the server.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil

        // Close any pending response connections
        for (_, fd) in pendingResponseFDs {
            close(fd)
        }
        pendingResponseFDs.removeAll()

        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }

        unlink(socketPath)
        logger.info("Hook socket server stopped")
    }

    // MARK: - Response Sending

    /// Send a permission decision response back to the hook handler script.
    /// This writes JSON to the open connection and closes it, unblocking the script.
    ///
    /// For AskUserQuestion, pass `updatedInput` with the original questions and an `answers`
    /// dict mapping question text to selected option labels.
    func sendPermissionResponse(sessionId: String, decision: String, updatedInput: [String: Any]? = nil) {
        guard let fd = pendingResponseFDs.removeValue(forKey: sessionId) else {
            logger.warning("No pending hook connection for session \(sessionId) to send response")
            return
        }

        // Claude Code expects this structure from PermissionRequest hook stdout:
        // { "hookSpecificOutput": { "hookEventName": "PermissionRequest", "decision": { "behavior": "allow"|"deny" } } }
        // For AskUserQuestion, include updatedInput with answers inside the decision:
        // { ..., "decision": { "behavior": "allow", "updatedInput": { "questions": [...], "answers": {...} } } }
        var decisionDict: [String: Any] = ["behavior": decision]
        if let updatedInput {
            decisionDict["updatedInput"] = updatedInput
        }

        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionDict
            ]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response) else {
            logger.error("Failed to encode permission response")
            close(fd)
            return
        }

        logger.info("Sending permission response: \(decision) to session \(sessionId) fd=\(fd)")

        // Write the response JSON and close
        jsonData.withUnsafeBytes { bufPtr in
            guard let base = bufPtr.baseAddress else { return }
            var sent = 0
            while sent < jsonData.count {
                let n = write(fd, base + sent, jsonData.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }

        close(fd)
    }

    // MARK: - Client Handling

    /// Accept all pending connections (multiple hooks can fire simultaneously).
    private func acceptClients() {
        while true {
            var clientAddr = sockaddr_un()
            var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &addrLen)
                }
            }

            guard clientFD >= 0 else { break }

            logger.debug("Hook client connected (fd=\(clientFD))")

            // Read on concurrent queue so one blocking read doesn't prevent others.
            readQueue.async { [weak self] in
                self?.readHookEvent(fd: clientFD)
            }
        }
    }

    /// Get the PID of a connected Unix socket peer.
    private nonisolated func getPeerPID(fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        // LOCAL_PEERPID = 0x002 on Darwin
        let result = getsockopt(fd, SOL_LOCAL, 0x002, &pid, &pidLen)
        return result == 0 && pid > 0 ? pid : nil
    }

    /// Read all data from a hook client connection until EOF (write shutdown), then parse.
    /// For PermissionRequest events, keep the connection open for sending a response.
    private nonisolated func readHookEvent(fd: Int32) {
        // Capture the hook handler's PID before reading data
        let peerPID = getPeerPID(fd: fd)

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)

        // Read until EOF or error (the client shuts down its write side after sending)
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                data.append(contentsOf: buf[..<n])
            } else {
                // EOF (n == 0) or error (n < 0)
                break
            }
        }

        guard !data.isEmpty else {
            close(fd)
            return
        }

        // Parse JSON
        do {
            var event = try JSONDecoder().decode(HookEvent.self, from: data)
            // Inject the hook handler's PID for process-tree based PTY resolution
            event.hookPeerPID = peerPID

            if event.hookEventName == "PermissionRequest" {
                // Keep connection open for response — store the fd
                Task { await self.handlePermissionEvent(event, clientFD: fd) }
            } else {
                // Fire-and-forget: close immediately
                close(fd)
                Task { await self.handleParsedEvent(event) }
            }
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            close(fd)
            Task { await self.logParseError(error, preview: preview) }
        }
    }

    private func handlePermissionEvent(_ event: HookEvent, clientFD: Int32) {
        logger.info("Hook event received (permission, fd=\(clientFD)): tool=\(event.toolName ?? "none") session=\(event.sessionId)")

        // Close any previous pending connection for this session
        if let oldFD = pendingResponseFDs.removeValue(forKey: event.sessionId) {
            logger.warning("Closing stale hook connection for session \(event.sessionId) fd=\(oldFD)")
            close(oldFD)
        }

        pendingResponseFDs[event.sessionId] = clientFD
        onHookEvent?(event)
    }

    private func handleParsedEvent(_ event: HookEvent) {
        logger.info("Hook event received: \(event.hookEventName) tool=\(event.toolName ?? "none") session=\(event.sessionId)")
        onHookEvent?(event)
    }

    private func logParseError(_ error: Error, preview: String) {
        logger.error("Failed to parse hook event: \(error.localizedDescription) — data: \(preview)")
    }
}
