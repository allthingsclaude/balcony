import Foundation

/// Multiplexed I/O bridge between local terminal, PTY master, and Unix socket.
///
/// Data flows:
/// 1. PTY master → local stdout (user sees output normally)
/// 2. PTY master → Unix socket (Mac agent gets raw bytes)
/// 3. Unix socket → PTY master (iOS input reaches claude)
/// 4. Local stdin → PTY master (local keyboard still works)
final class IOBridge {
    private let masterFD: Int32
    private let childPID: pid_t
    private let socketClient: SocketClient?

    // Separate queues to prevent one blocking the other
    private let masterQueue = DispatchQueue(label: "com.balcony.cli.master", qos: .userInteractive)
    private let stdinQueue = DispatchQueue(label: "com.balcony.cli.stdin", qos: .userInteractive)
    private let socketQueue = DispatchQueue(label: "com.balcony.cli.socket", qos: .utility)

    private var masterReadSource: DispatchSourceRead?
    private var stdinReadSource: DispatchSourceRead?

    /// Saved terminal attributes for restoring on exit.
    private var savedTermios: termios?

    /// Called when the PTY master returns EIO (slave closed, child exited).
    /// Used as a fallback exit mechanism if the process source misses the exit.
    var onPTYClosed: (() -> Void)?

    init(masterFD: Int32, childPID: pid_t, socketClient: SocketClient?) {
        self.masterFD = masterFD
        self.childPID = childPID
        self.socketClient = socketClient
    }

    /// Start the I/O bridge.
    func start() {
        // Put local stdin into raw mode so keystrokes pass through immediately
        enableRawMode()

        // Set master FD to non-blocking to prevent read() from hanging
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // Wire up socket → PTY for remote input
        socketClient?.onMessage = { [weak self] type, data in
            guard let self else {
                Self.debugLog("onMessage: self is nil!")
                return
            }
            Self.debugLog("onMessage: type=\(type) bytes=\(data.count)")
            switch type {
            case .ptyInput:
                // Write remote input to PTY master
                data.withUnsafeBytes { bufPtr in
                    guard let base = bufPtr.baseAddress else { return }
                    let n = write(self.masterFD, base, data.count)
                    Self.debugLog("ptyInput: wrote \(n)/\(data.count) bytes to masterFD=\(self.masterFD) errno=\(n < 0 ? errno : 0)")
                }
            case .resize:
                // Parse cols/rows and resize PTY
                if data.count >= 4 {
                    let cols = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self).bigEndian }
                    let rows = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                    fputs("[balcony] Resize from iOS: \(cols)x\(rows)\n", stderr)
                    // iOS now owns the PTY size — suppress local SIGWINCH resizes
                    remoteControlsResize = true
                    PTYManager.setWindowSize(masterFD: self.masterFD, cols: cols, rows: rows)
                    kill(self.childPID, SIGWINCH)
                }
            default:
                break
            }
        }

        // Read from PTY master → stdout + socket (on its own queue)
        let masterSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: masterQueue)
        masterSource.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 16384)
            let n = read(self.masterFD, &buf, buf.count)
            if n > 0 {
                // Mirror to local stdout (stdout is blocking, which is fine)
                _ = write(STDOUT_FILENO, &buf, n)
                // Forward to Mac agent socket on a separate queue to avoid blocking
                let data = Data(buf[..<n])
                self.socketQueue.async {
                    self.socketClient?.sendPTYOutput(data)
                }
            }
            if n <= 0 && errno != EAGAIN && errno != EINTR {
                // EIO or EOF: PTY slave was closed (child exited).
                // Dispatch to main to avoid cancelling this source from its own handler.
                let callback = self.onPTYClosed
                DispatchQueue.main.async { callback?() }
            }
        }
        masterSource.resume()
        masterReadSource = masterSource

        // Read from local stdin → PTY master (on its own queue)
        let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: stdinQueue)
        stdinSource.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(STDIN_FILENO, &buf, buf.count)
            if n > 0 {
                _ = write(self.masterFD, &buf, n)
            }
        }
        stdinSource.resume()
        stdinReadSource = stdinSource
    }

    /// Stop the I/O bridge and restore terminal state.
    func stop() {
        masterReadSource?.cancel()
        masterReadSource = nil
        stdinReadSource?.cancel()
        stdinReadSource = nil
        restoreTerminalMode()
    }

    // MARK: - Debug Logging

    private static func debugLog(_ msg: String) {
        let line = "[\(Date())] CLI: \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = "/tmp/balcony-debug.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        }
    }

    // MARK: - Raw Terminal Mode

    private func enableRawMode() {
        guard isatty(STDIN_FILENO) != 0 else { return }
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        savedTermios = raw
        cfmakeraw(&raw)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func restoreTerminalMode() {
        guard var saved = savedTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
        savedTermios = nil
    }
}
