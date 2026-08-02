import Foundation

// MARK: - Find claude executable

func findClaude() -> String? {
    // Check common locations
    let candidates = [
        "/usr/local/bin/claude",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/local/claude",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
    ]

    for path in candidates {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    // Try `which claude`
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["claude"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
    }

    return nil
}

// MARK: - Cleanup & exit

/// Guard against cleanup being called twice (process source + PTY EIO can race).
var cleanupCalled = false

func cleanup(status: Int32) -> Never {
    guard !cleanupCalled else { dispatchMain() }
    cleanupCalled = true

    bridge.stop()
    close(pty.masterFD)

    socketClient.sendSessionEnded()
    socketClient.stopAndDisconnect()

    // WIFEXITED / WEXITSTATUS replicated — these are C macros unavailable in Swift
    let childExited = (status & 0x7f) == 0
    if childExited {
        let exitCode = (status >> 8) & 0xff
        exit(Int32(exitCode))
    } else {
        exit(1)
    }
}

// MARK: - Main

// Ignore SIGPIPE — broken socket writes return EPIPE instead of terminating us.
signal(SIGPIPE, SIG_IGN)

guard let claudePath = findClaude() else {
    fputs("Error: Could not find 'claude' executable. Make sure Claude Code CLI is installed.\n", stderr)
    exit(1)
}

// Forward all args after "balcony" to claude
let claudeArgs = Array(CommandLine.arguments.dropFirst())
let fullArgs = ["claude"] + claudeArgs

// Create the PTY
let pty: PTYManager.PTYPair
do {
    pty = try PTYManager.createPTY()
} catch {
    fputs("Error: Failed to create PTY: \(error)\n", stderr)
    exit(1)
}

// Connect to Mac agent socket (optional — works without it).
// If the Mac agent isn't running yet, a reconnect loop will keep trying.
let socketClient = SocketClient()
var socketConnected = socketClient.connect()
if !socketConnected {
    fputs("[balcony] Mac agent not running — will retry in background\n", stderr)
}

// Set initial PTY size to match the local Mac terminal. This must happen before the
// child is spawned, otherwise claude reads a 0x0 tty and lays itself out at 80x24.
// `createPTY` has already opened the slave, which is what makes TIOCSWINSZ legal here.
// When iOS connects it will send its own size, which takes priority.
let (cols, rows) = PTYManager.getWindowSize(fd: STDOUT_FILENO)
if !PTYManager.setWindowSize(masterFD: pty.masterFD, cols: cols, rows: rows) {
    fputs("[balcony] Warning: could not set initial PTY size (\(cols)x\(rows))\n", stderr)
}

/// Once iOS sends a resize, it owns the PTY size — local SIGWINCH is ignored
/// so that resizing the Mac terminal window doesn't break the iOS display.
var remoteControlsResize = false

/// PID of the spawned child, or 0 before `posix_spawn` returns. The SIGWINCH handler is
/// installed ahead of the spawn — SIGWINCH's default disposition is "ignore", so a resize
/// arriving during claude's startup would otherwise be dropped — and guards on this.
var childPID: pid_t = 0

// Handle SIGWINCH — forward terminal resize to PTY and child,
// but only if iOS hasn't taken control of the PTY size.
signal(SIGWINCH) { _ in
    guard !remoteControlsResize else { return }
    let (newCols, newRows) = PTYManager.getWindowSize(fd: STDOUT_FILENO)
    PTYManager.setWindowSize(masterFD: pty.masterFD, cols: newCols, rows: newRows)
    if childPID > 0 { kill(childPID, SIGWINCH) }
}

// Generate a session ID
let sessionId = UUID().uuidString

// Build environment — inherit current env + set TERM + inject PTY session ID
var env = ProcessInfo.processInfo.environment
env["TERM"] = env["TERM"] ?? "xterm-256color"
env["BALCONY_PTY_SESSION_ID"] = sessionId
let envStrings = env.map { "\($0.key)=\($0.value)" }

// Spawn claude in the PTY
do {
    childPID = try PTYManager.spawnProcess(
        executable: claudePath,
        args: fullArgs,
        slaveFD: pty.slaveFD,
        env: envStrings
    )
} catch {
    fputs("Error: Failed to spawn claude: \(error)\n", stderr)
    close(pty.slaveFD)
    close(pty.masterFD)
    exit(1)
}

// Drop our copy of the slave now that the child has inherited it via dup2. If we kept it
// open the master would never see EIO, and the `onPTYClosed` exit path would never fire.
close(pty.slaveFD)

// Build session info (used on connect and reconnect)
let cwd = FileManager.default.currentDirectoryPath
let sessionInfo = PTYSessionInfo(
    sessionId: sessionId,
    pid: childPID,
    cwd: cwd,
    args: claudeArgs.joined(separator: " "),
    cols: cols,
    rows: rows
)

// Send session info now if connected
if socketConnected {
    socketClient.sendSessionInfo(sessionInfo)
}

// Re-send session info whenever we (re)connect to the Mac agent
socketClient.onConnected = {
    socketConnected = true
    fputs("[balcony] Connected to Mac agent\n", stderr)
    socketClient.sendSessionInfo(sessionInfo)
}

// Start reconnect loop so late-started Mac agent picks up this session
socketClient.startReconnectLoop()

// Set up the I/O bridge — always pass the client so output forwards once connected
let bridge = IOBridge(masterFD: pty.masterFD, childPID: childPID, socketClient: socketClient)

// Fallback: if PTY master returns EIO (slave closed), the child has exited.
// This catches cases where the process source might not fire.
bridge.onPTYClosed = {
    var status: Int32 = 0
    let result = waitpid(childPID, &status, WNOHANG)
    if result > 0 {
        cleanup(status: status)
    } else {
        cleanup(status: 0)
    }
}

// Handle SIGINT — forward to child instead of killing ourselves
signal(SIGINT) { _ in
    kill(childPID, SIGINT)
}

// Handle SIGTERM — clean shutdown
signal(SIGTERM) { _ in
    kill(childPID, SIGTERM)
}

// Monitor child process for exit using a process-specific dispatch source.
// This uses kqueue(EVFILT_PROC) under the hood and avoids the SIGCHLD + SIG_IGN
// race where auto-reaping causes waitpid to fail with ECHILD.
let processSource = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: .main)
processSource.setEventHandler {
    var status: Int32 = 0
    let result = waitpid(childPID, &status, WNOHANG)
    if result > 0 {
        cleanup(status: status)
    } else {
        // Child was already reaped — exit cleanly
        cleanup(status: 0)
    }
}
processSource.resume()

// Start the I/O bridge
bridge.start()

// Re-check terminal size shortly after startup. Some terminal emulators
// (split panes, new tabs) finalize TIOCGWINSZ after the child spawns,
// so the initial read may be stale. Forward any change to the child — but stay silent
// when nothing moved, so a correctly-sized session isn't forced into a needless relayout.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    guard !remoteControlsResize else { return }
    let (refreshCols, refreshRows) = PTYManager.getWindowSize(fd: STDOUT_FILENO)
    if let applied = PTYManager.currentWindowSize(masterFD: pty.masterFD),
       applied == (refreshCols, refreshRows) {
        return
    }
    PTYManager.setWindowSize(masterFD: pty.masterFD, cols: refreshCols, rows: refreshRows)
    kill(childPID, SIGWINCH)
}

// Enter the GCD main run loop — never returns.
// Exit happens via the process source or PTY EIO fallback calling cleanup().
dispatchMain()
