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
    private let socketClient: SocketClient?

    // Separate queues to prevent one blocking the other
    private let masterQueue = DispatchQueue(label: "com.balcony.cli.master", qos: .userInteractive)
    private let stdinQueue = DispatchQueue(label: "com.balcony.cli.stdin", qos: .userInteractive)
    private let socketQueue = DispatchQueue(label: "com.balcony.cli.socket", qos: .utility)

    private var masterReadSource: DispatchSourceRead?
    private var stdinReadSource: DispatchSourceRead?

    /// Saved terminal attributes for restoring on exit.
    private var savedTermios: termios?

    init(masterFD: Int32, socketClient: SocketClient?) {
        self.masterFD = masterFD
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
            guard let self else { return }
            switch type {
            case .ptyInput:
                // Write remote input to PTY master
                data.withUnsafeBytes { bufPtr in
                    guard let base = bufPtr.baseAddress else { return }
                    _ = write(self.masterFD, base, data.count)
                }
            case .resize:
                // Parse cols/rows and resize PTY
                if data.count >= 4 {
                    let cols = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self).bigEndian }
                    let rows = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                    PTYManager.setWindowSize(masterFD: self.masterFD, cols: cols, rows: rows)
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
            // n == 0 or EAGAIN: no data right now, dispatch source will fire again
            // n < 0 && errno != EAGAIN: PTY closed (child exited), handled by SIGCHLD
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
