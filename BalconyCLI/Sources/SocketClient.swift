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

    /// Called when data arrives from the Mac agent (e.g. iOS input, resize).
    var onMessage: ((SocketMessageType, Data) -> Void)?

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
    }

    /// Send a framed message to the Mac agent.
    func send(type: SocketMessageType, data: Data) {
        guard connected, socketFD >= 0 else { return }

        // Header: [1-byte type][4-byte big-endian length]
        var header = Data(count: 5)
        header[0] = type.rawValue
        let len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: len) { header.replaceSubrange(1..<5, with: $0) }

        let fullMessage = header + data
        fullMessage.withUnsafeBytes { bufPtr in
            guard let base = bufPtr.baseAddress else { return }
            var sent = 0
            while sent < fullMessage.count {
                let n = write(socketFD, base + sent, fullMessage.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
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

    /// Send raw PTY output bytes.
    func sendPTYOutput(_ data: Data) {
        send(type: .ptyOutput, data: data)
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
