import Foundation

/// Framed protocol message types for the Unix domain socket.
enum SocketMessageType: UInt8 {
    /// PTY output: raw terminal bytes (CLI → Mac).
    case ptyOutput = 0x01
    /// PTY input: raw bytes to write to PTY master (Mac → CLI).
    case ptyInput = 0x02
    /// Resize: cols + rows as uint16 (Mac → CLI).
    case resize = 0x03
    /// Session info: JSON metadata (CLI → Mac).
    case sessionInfo = 0x04
    /// Session ended: child process exited (CLI → Mac).
    case sessionEnded = 0x05
    /// Stdin activity: user typed in the local terminal (CLI → Mac).
    case stdinActivity = 0x06
}

/// Session metadata sent from CLI to Mac on connect.
struct PTYSessionInfo: Codable {
    let sessionId: String
    let pid: Int32
    let cwd: String
    let args: String
    let cols: UInt16
    let rows: UInt16
}

/// Connects to BalconyMac's Unix domain socket and exchanges framed messages.
///
/// Wire format: `[1-byte type][4-byte big-endian length][payload]`
final class SocketClient {
    private let socketPath: String
    private var socketFD: Int32 = -1
    private var connected = false
    private let readQueue = DispatchQueue(label: "com.balcony.cli.socket.read")
    private var readSource: DispatchSourceRead?

    /// Serial queue for all writes — preserves frame ordering and lets us
    /// reason about pendingBytes from a single thread.
    private let writeQueue = DispatchQueue(label: "com.balcony.cli.socket.write", qos: .utility)
    /// Bytes currently queued but not yet handed to the kernel.
    private var pendingBytes = 0
    /// Drop new PTY-output frames if pending exceeds this. The user still sees
    /// output locally; only the remote mirror skips ahead.
    private static let maxPendingBytes = 4 * 1024 * 1024
    /// True after we've dropped at least one chunk in the current congestion episode.
    private var dropping = false

    /// Called when data arrives from the Mac agent (e.g. iOS input, resize).
    var onMessage: ((SocketMessageType, Data) -> Void)?

    /// Called when a connection (or reconnection) to the Mac agent succeeds.
    var onConnected: (() -> Void)?

    /// Timer for periodic reconnection attempts.
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectEnabled = false

    init(socketPath: String? = nil) {
        if let path = socketPath {
            self.socketPath = path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.socketPath = "\(home)/.balcony/pty.sock"
        }
    }

    /// Attempt to connect to the Mac agent's Unix domain socket.
    /// Returns `true` if connection succeeded, `false` if socket doesn't exist.
    func connect() -> Bool {
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(socketFD)
            socketFD = -1
            return false
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(pathBytes.count)) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(socketFD, sockPtr, addrLen)
            }
        }

        if result != 0 {
            close(socketFD)
            socketFD = -1
            return false
        }

        // Non-blocking writes — combined with the writeQueue + pendingBytes
        // budget, this prevents a slow Mac agent from hanging the CLI.
        let flags = fcntl(socketFD, F_GETFL)
        _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)

        writeQueue.sync {
            pendingBytes = 0
            dropping = false
        }
        connected = true
        startReading()
        return true
    }

    /// Disconnect from the socket.
    func disconnect() {
        readSource?.cancel()
        readSource = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        connected = false

        // If reconnect is enabled, the timer will pick up and retry
    }

    /// Start a background reconnect loop that periodically tries to connect
    /// if not already connected. Calls `onConnected` on success.
    func startReconnectLoop(interval: TimeInterval = 3.0) {
        reconnectEnabled = true

        let timer = DispatchSource.makeTimerSource(queue: readQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.reconnectEnabled, !self.connected else { return }
            if self.connect() {
                self.onConnected?()
            }
        }
        timer.resume()
        reconnectTimer = timer
    }

    /// Stop the reconnect loop and disconnect.
    func stopAndDisconnect() {
        reconnectEnabled = false
        reconnectTimer?.cancel()
        reconnectTimer = nil
        disconnect()
    }

    /// Send a framed message to the Mac agent. Always-deliver: blocks the write
    /// queue until the kernel accepts the bytes (used for control messages).
    func send(type: SocketMessageType, data: Data) {
        enqueue(type: type, data: data, droppable: false)
    }

    /// Send session info JSON.
    func sendSessionInfo(_ info: PTYSessionInfo) {
        guard let jsonData = try? JSONEncoder().encode(info) else { return }
        send(type: .sessionInfo, data: jsonData)
    }

    /// Send session ended notification.
    func sendSessionEnded() {
        send(type: .sessionEnded, data: Data())
    }

    /// Send raw PTY output bytes. Droppable when the send queue is saturated —
    /// the local terminal already shows the output, so a slow Mac agent must
    /// not back-pressure into a hang.
    func sendPTYOutput(_ data: Data) {
        enqueue(type: .ptyOutput, data: data, droppable: true)
    }

    private func enqueue(type: SocketMessageType, data: Data, droppable: Bool) {
        guard connected, socketFD >= 0 else { return }

        let frameSize = 5 + data.count
        writeQueue.async { [weak self] in
            guard let self, self.connected, self.socketFD >= 0 else { return }

            if droppable {
                if self.pendingBytes + frameSize > Self.maxPendingBytes {
                    if !self.dropping {
                        self.dropping = true
                        fputs("[balcony] Mac agent slow — pausing remote mirror\n", stderr)
                    }
                    return
                } else if self.dropping && self.pendingBytes == 0 {
                    self.dropping = false
                    fputs("[balcony] Mac agent caught up — resuming remote mirror\n", stderr)
                }
            }

            self.pendingBytes += frameSize

            var header = Data(count: 5)
            header[0] = type.rawValue
            let len = UInt32(data.count).bigEndian
            withUnsafeBytes(of: len) { header.replaceSubrange(1..<5, with: $0) }
            let frame = header + data

            frame.withUnsafeBytes { bufPtr in
                guard let base = bufPtr.bindMemory(to: UInt8.self).baseAddress else { return }
                self.writeFrame(base, count: frame.count, droppable: droppable)
            }

            self.pendingBytes -= frameSize
            if self.pendingBytes < 0 { self.pendingBytes = 0 }
        }
    }

    /// Drain a frame to socketFD. Loops on EINTR; on EAGAIN, polls briefly.
    /// For droppable frames, gives up after a short stall instead of blocking
    /// the writeQueue forever.
    private func writeFrame(_ ptr: UnsafePointer<UInt8>, count: Int, droppable: Bool) {
        var sent = 0
        var stalls = 0
        let maxStalls = droppable ? 4 : 100   // ~200ms vs ~5s
        while sent < count {
            let n = write(socketFD, ptr + sent, count - sent)
            if n > 0 { sent += n; stalls = 0; continue }
            if n < 0 && errno == EINTR { continue }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                stalls += 1
                if stalls > maxStalls {
                    // Frame is half-written — the stream is now desynced.
                    // Drop the connection so the reconnect loop re-handshakes.
                    fputs("[balcony] Socket write stalled — disconnecting\n", stderr)
                    let fd = socketFD
                    socketFD = -1
                    connected = false
                    if fd >= 0 { close(fd) }
                    return
                }
                var pfd = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pfd, 1, 50)
                continue
            }
            // EPIPE / ECONNRESET / other fatal — disconnect.
            let fd = socketFD
            socketFD = -1
            connected = false
            if fd >= 0 { close(fd) }
            return
        }
    }

    /// Notify Mac agent that the user typed in the local terminal.
    func sendStdinActivity() {
        send(type: .stdinActivity, data: Data())
    }

    // MARK: - Reading

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: readQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler { [weak self] in
            self?.connected = false
        }
        source.resume()
        readSource = source
    }

    private var readBuffer = Data()

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = read(socketFD, &buf, buf.count)
        if n <= 0 {
            // Connection closed or error
            disconnect()
            return
        }

        readBuffer.append(contentsOf: buf[..<n])

        // Parse framed messages: [1-byte type][4-byte length][payload]
        while readBuffer.count >= 5 {
            let msgType = readBuffer[readBuffer.startIndex]
            let lenBytes = readBuffer.subdata(in: (readBuffer.startIndex + 1)..<(readBuffer.startIndex + 5))
            let len = lenBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let totalLen = 5 + Int(len)

            guard readBuffer.count >= totalLen else { break }

            let payload = readBuffer.subdata(in: (readBuffer.startIndex + 5)..<(readBuffer.startIndex + totalLen))
            readBuffer.removeFirst(totalLen)

            if let type = SocketMessageType(rawValue: msgType) {
                onMessage?(type, payload)
            }
        }
    }

}
