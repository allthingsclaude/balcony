import Foundation
import BalconyShared
import os

/// Listens for Claude Code hook events via a Unix domain socket.
///
/// Claude Code's async hooks pipe JSON to a handler script's stdin.
/// The handler script connects to this socket and writes the JSON.
/// Each connection represents one hook event: read until EOF, parse, close.
actor HookListener {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookListener")

    private let socketPath: String
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.balcony.mac.hooks.io", qos: .userInteractive)

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

        guard listen(serverFD, 5) == 0 else {
            close(serverFD)
            serverFD = -1
            throw POSIXError(.init(rawValue: errno) ?? .EOPNOTSUPP)
        }

        logger.info("Hook socket server listening at \(self.socketPath)")

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: ioQueue)
        source.setEventHandler { [weak self] in
            Task { await self?.acceptClient() }
        }
        source.resume()
        acceptSource = source
    }

    /// Stop the server.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil

        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }

        unlink(socketPath)
        logger.info("Hook socket server stopped")
    }

    // MARK: - Client Handling

    private func acceptClient() {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverFD, sockPtr, &addrLen)
            }
        }

        guard clientFD >= 0 else { return }

        logger.debug("Hook client connected (fd=\(clientFD))")

        // Read the entire JSON payload from this connection on a background queue.
        // Each connection = one hook event, read until EOF.
        ioQueue.async { [weak self] in
            self?.readHookEvent(fd: clientFD)
        }
    }

    /// Read all data from a hook client connection until EOF, then parse as JSON.
    private nonisolated func readHookEvent(fd: Int32) {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)

        // Read until EOF or error
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                data.append(contentsOf: buf[..<n])
            } else {
                // EOF (n == 0) or error (n < 0)
                break
            }
        }

        close(fd)

        guard !data.isEmpty else { return }

        // Parse JSON
        do {
            let event = try JSONDecoder().decode(HookEvent.self, from: data)
            Task { await self.handleParsedEvent(event) }
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            Task { await self.logParseError(error, preview: preview) }
        }
    }

    private func handleParsedEvent(_ event: HookEvent) {
        logger.info("Hook event received: \(event.hookEventName) tool=\(event.toolName ?? "none") session=\(event.sessionId)")
        onHookEvent?(event)
    }

    private func logParseError(_ error: Error, preview: String) {
        logger.error("Failed to parse hook event: \(error.localizedDescription) — data: \(preview)")
    }
}
