import Foundation
import BalconyShared
import os

/// Events emitted by PTY session lifecycle changes.
enum SessionEvent: Sendable {
    case sessionDiscovered(Session)
    case sessionEnded(String)
}

/// Manages live PTY sessions from CLI connections via a Unix domain socket.
actor PTYSessionManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "PTYSessionManager")

    private let socketPath: String
    private var serverFD: Int32 = -1
    private var clientFDs: [Int32: PTYClientState] = [:]
    private var sessions: [String: Session] = [:]
    private var acceptSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.balcony.mac.pty.io", qos: .userInteractive)

    /// Called when a PTY session is discovered, updated, or ended.
    private var onSessionEvent: (@Sendable (SessionEvent) -> Void)?

    /// Called when raw PTY output arrives for a session.
    private var onPTYOutput: (@Sendable (String, Data) -> Void)?

    /// Set the session event callback.
    func setOnSessionEvent(_ handler: @escaping @Sendable (SessionEvent) -> Void) {
        onSessionEvent = handler
    }

    /// Set the PTY output callback.
    func setOnPTYOutput(_ handler: @escaping @Sendable (String, Data) -> Void) {
        onPTYOutput = handler
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.socketPath = "\(home)/.balcony/pty.sock"
    }

    // MARK: - Lifecycle

    /// Start the Unix domain socket server.
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

        // Set server fd to non-blocking so accept() never blocks the actor
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

        logger.info("PTY socket server listening at \(self.socketPath)")

        // Accept connections asynchronously
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: ioQueue)
        source.setEventHandler { [weak self] in
            Task { await self?.acceptClient() }
        }
        source.resume()
        acceptSource = source
    }

    /// Stop the server and close all connections.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil

        for (fd, state) in clientFDs {
            state.readSource?.cancel()
            close(fd)
        }
        clientFDs.removeAll()
        sessions.removeAll()

        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }

        unlink(socketPath)
        logger.info("PTY socket server stopped")
    }

    // MARK: - Client Management

    private func acceptClient() {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverFD, sockPtr, &addrLen)
            }
        }

        guard clientFD >= 0 else { return }

        // Set client fd to non-blocking so read() never blocks the actor
        let cflags = fcntl(clientFD, F_GETFL)
        _ = fcntl(clientFD, F_SETFL, cflags | O_NONBLOCK)

        logger.info("CLI client connected (fd=\(clientFD))")

        let state = PTYClientState()

        // Set up read source for this client
        let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: ioQueue)
        readSource.setEventHandler { [weak self] in
            Task { await self?.readFromClient(fd: clientFD) }
        }
        readSource.setCancelHandler { [weak self] in
            Task { await self?.clientDisconnected(fd: clientFD) }
        }
        readSource.resume()
        state.readSource = readSource

        clientFDs[clientFD] = state
    }

    private func readFromClient(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &buf, buf.count)

        if n == 0 {
            // EOF — client disconnected
            clientDisconnected(fd: fd)
            return
        }
        if n < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // No data available right now — dispatch source will fire again
                return
            }
            // Real error
            clientDisconnected(fd: fd)
            return
        }

        guard let state = clientFDs[fd] else { return }
        state.buffer.append(contentsOf: buf[..<n])

        // Parse framed messages: [1-byte type][4-byte big-endian length][payload]
        // Use Array for zero-based indexing (Data.removeFirst shifts startIndex)
        while state.buffer.count >= 5 {
            let bytes = Array(state.buffer)
            let msgType = bytes[0]
            let len = UInt32(bytes[1]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 8 | UInt32(bytes[4])
            let totalLen = 5 + Int(len)

            guard bytes.count >= totalLen else { break }

            let payload = Data(bytes[5..<totalLen])
            state.buffer = Data(bytes[totalLen...])

            handleClientMessage(fd: fd, type: msgType, payload: payload)
        }
    }

    private func handleClientMessage(fd: Int32, type: UInt8, payload: Data) {
        switch type {
        case 0x01: // PTY output
            guard let state = clientFDs[fd], let sessionId = state.sessionId else { return }
            onPTYOutput?(sessionId, payload)

        case 0x04: // Session info
            guard let info = try? JSONDecoder().decode(PTYSessionInfoMessage.self, from: payload) else {
                logger.error("Failed to decode session info from CLI")
                return
            }

            let session = Session(
                id: info.sessionId,
                projectPath: info.cwd,
                status: .active,
                cwd: info.cwd
            )
            sessions[info.sessionId] = session
            clientFDs[fd]?.sessionId = info.sessionId

            logger.info("PTY session registered: \(info.sessionId) (pid=\(info.pid), args=\(info.args))")
            onSessionEvent?(.sessionDiscovered(session))

        case 0x05: // Session ended
            guard let state = clientFDs[fd], let sessionId = state.sessionId else { return }
            sessions.removeValue(forKey: sessionId)
            logger.info("PTY session ended: \(sessionId)")
            onSessionEvent?(.sessionEnded(sessionId))

        default:
            break
        }
    }

    private func clientDisconnected(fd: Int32) {
        guard let state = clientFDs.removeValue(forKey: fd) else { return }
        state.readSource?.cancel()
        close(fd)

        if let sessionId = state.sessionId {
            sessions.removeValue(forKey: sessionId)
            logger.info("CLI client disconnected, session ended: \(sessionId)")
            onSessionEvent?(.sessionEnded(sessionId))
        } else {
            logger.info("CLI client disconnected (no session)")
        }
    }

    // MARK: - Sending to CLI

    /// Forward input from iOS to the CLI's PTY via the Unix socket.
    func sendInput(sessionId: String, data: Data) {
        guard let fd = clientFDForSession(sessionId) else {
            logger.warning("No CLI connection for session \(sessionId)")
            return
        }
        sendFramed(fd: fd, type: 0x02, data: data)
    }

    /// Forward a resize event from iOS to the CLI's PTY.
    func sendResize(sessionId: String, cols: UInt16, rows: UInt16) {
        guard let fd = clientFDForSession(sessionId) else { return }
        var data = Data(count: 4)
        let bigCols = cols.bigEndian
        let bigRows = rows.bigEndian
        withUnsafeBytes(of: bigCols) { data.replaceSubrange(0..<2, with: $0) }
        withUnsafeBytes(of: bigRows) { data.replaceSubrange(2..<4, with: $0) }
        sendFramed(fd: fd, type: 0x03, data: data)
    }

    /// Get active PTY sessions.
    func getActiveSessions() -> [Session] {
        Array(sessions.values)
    }

    // MARK: - Helpers

    private func clientFDForSession(_ sessionId: String) -> Int32? {
        for (fd, state) in clientFDs where state.sessionId == sessionId {
            return fd
        }
        return nil
    }

    private func sendFramed(fd: Int32, type: UInt8, data: Data) {
        var header = Data(count: 5)
        header[0] = type
        let len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: len) { header.replaceSubrange(1..<5, with: $0) }

        let fullMessage = header + data
        fullMessage.withUnsafeBytes { bufPtr in
            guard let base = bufPtr.baseAddress else { return }
            var sent = 0
            while sent < fullMessage.count {
                let n = write(fd, base + sent, fullMessage.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}

// MARK: - Supporting Types

/// Mutable state for a connected CLI client.
private final class PTYClientState {
    var readSource: DispatchSourceRead?
    var sessionId: String?
    var buffer = Data()
}

/// Session info JSON sent from CLI to Mac.
private struct PTYSessionInfoMessage: Codable {
    let sessionId: String
    let pid: Int32
    let cwd: String
    let args: String
    let cols: UInt16
    let rows: UInt16
}
