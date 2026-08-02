import Foundation

/// Manages pseudoterminal creation and child process spawning.
enum PTYManager {

    /// Result of creating a PTY pair.
    struct PTYPair {
        let masterFD: Int32
        /// The slave side, already open. Ownership passes to the caller, which must
        /// `close()` it once the child has inherited it (see `spawnProcess`).
        let slaveFD: Int32
        let slavePath: String
    }

    /// Create a PTY master/slave pair, with the slave side already opened.
    static func createPTY() throws -> PTYPair {
        let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .ENODEV)
        }

        // Don't let the PTY master leak across exec into claude or its grandchildren — only
        // the CLI process should hold it (whoever holds the master can read everything typed).
        _ = fcntl(masterFD, F_SETFD, FD_CLOEXEC)

        guard grantpt(masterFD) == 0 else {
            close(masterFD)
            throw POSIXError(.init(rawValue: errno) ?? .EACCES)
        }

        guard unlockpt(masterFD) == 0 else {
            close(masterFD)
            throw POSIXError(.init(rawValue: errno) ?? .EACCES)
        }

        guard let slaveNameC = ptsname(masterFD) else {
            close(masterFD)
            throw POSIXError(.init(rawValue: errno) ?? .ENOTTY)
        }

        let slavePath = String(cString: slaveNameC)

        // Open the slave *here*, not in `spawnProcess`. On macOS TIOCSWINSZ against the
        // master fails with ENOTTY until the slave has been opened at least once, so
        // sizing the PTY before this point is a silent no-op — the child would start on a
        // 0x0 tty and fall back to terminfo's 80x24.
        let slaveFD = open(slavePath, O_RDWR)
        guard slaveFD >= 0 else {
            close(masterFD)
            throw POSIXError(.init(rawValue: errno) ?? .ENOENT)
        }

        return PTYPair(masterFD: masterFD, slaveFD: slaveFD, slavePath: slavePath)
    }

    /// Set the terminal window size on the PTY master.
    ///
    /// - Returns: `false` if the ioctl failed. The usual cause is calling this before the
    ///   PTY slave has ever been opened, which macOS rejects with ENOTTY.
    @discardableResult
    static func setWindowSize(masterFD: Int32, cols: UInt16, rows: UInt16) -> Bool {
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        return ioctl(masterFD, TIOCSWINSZ, &ws) == 0
    }

    /// Read the window size currently applied to the PTY master.
    static func currentWindowSize(masterFD: Int32) -> (cols: UInt16, rows: UInt16)? {
        var ws = winsize()
        guard ioctl(masterFD, TIOCGWINSZ, &ws) == 0 else { return nil }
        return (ws.ws_col, ws.ws_row)
    }

    /// Get the current terminal window size from a file descriptor.
    /// Tries stdin, stdout, and stderr in order so that one redirected fd
    /// doesn't cause a zero-size fallback. Returns (80, 24) if all fail.
    static func getWindowSize(fd: Int32) -> (cols: UInt16, rows: UInt16) {
        for tryFD in [fd, STDIN_FILENO, STDERR_FILENO] {
            var ws = winsize()
            if ioctl(tryFD, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
                return (ws.ws_col, ws.ws_row)
            }
        }
        return (80, 24)
    }

    /// Spawn a child process attached to the PTY slave.
    ///
    /// - Parameters:
    ///   - executable: Full path to the executable.
    ///   - args: Arguments (including argv[0]).
    ///   - slaveFD: Open descriptor for the PTY slave (from `createPTY`). Still owned by
    ///     the caller, which must close it once this returns so that the master reports
    ///     EIO when the child exits.
    ///   - env: Environment variables as `KEY=VALUE` strings.
    /// - Returns: PID of the spawned process.
    static func spawnProcess(
        executable: String,
        args: [String],
        slaveFD: Int32,
        env: [String]
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        // Redirect stdin/stdout/stderr to the PTY slave
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)

        var spawnAttrs: posix_spawnattr_t?
        posix_spawnattr_init(&spawnAttrs)
        // Start a new session so the child gets a controlling terminal
        posix_spawnattr_setflags(&spawnAttrs, Int16(POSIX_SPAWN_SETSID))

        // Convert args to C strings
        let cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { cArgs.forEach { if let p = $0 { free(p) } } }
        var argv = cArgs + [nil]

        // Convert env to C strings
        let cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0) }
        defer { cEnv.forEach { if let p = $0 { free(p) } } }
        var envp = cEnv + [nil]

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &fileActions, &spawnAttrs, &argv, &envp)

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&spawnAttrs)

        guard result == 0 else {
            throw POSIXError(.init(rawValue: result) ?? .ENOEXEC)
        }

        return pid
    }
}
