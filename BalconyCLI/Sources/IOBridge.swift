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
            guard let self else { return }
            switch type {
            case .ptyInput:
                // Write remote input to PTY master (loop with poll on EAGAIN —
                // pasting more than the PTY input queue holds would otherwise drop bytes).
                data.withUnsafeBytes { bufPtr in
                    guard let base = bufPtr.bindMemory(to: UInt8.self).baseAddress else { return }
                    Self.writeAll(self.masterFD, base, data.count)
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
                // Forward to Mac agent — droppable under backpressure.
                self.socketClient?.sendPTYOutput(Data(buf[..<n]))
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
                Self.writeAll(self.masterFD, &buf, n)
                // Notify Mac agent on actual user input (not escape sequences).
                // Terminal focus events (\e[I, \e[O), arrow keys, function keys
                // all start with ESC (0x1B) — skip those.
                if buf[0] != 0x1B {
                    self.socketClient?.sendStdinActivity()
                }
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

    // MARK: - Write helper

    /// Drain a buffer to a (possibly non-blocking) fd, retrying on EAGAIN/EINTR.
    /// Without this, pastes larger than the PTY input queue (~1–8 KB on macOS)
    /// are silently truncated.
    static func writeAll(_ fd: Int32, _ ptr: UnsafePointer<UInt8>, _ count: Int) {
        var sent = 0
        while sent < count {
            let n = write(fd, ptr + sent, count - sent)
            if n > 0 { sent += n; continue }
            if n < 0 && errno == EINTR { continue }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pfd, 1, 1000)
                continue
            }
            break
        }
    }
}
