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

    if socketConnected {
        socketClient.sendSessionEnded()
        socketClient.disconnect()
    }

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

// Connect to Mac agent socket (optional — works without it)
let socketClient = SocketClient()
let socketConnected = socketClient.connect()
if socketConnected {
    fputs("[balcony] Connected to Mac agent\n", stderr)
} else {
    fputs("[balcony] Mac agent not running (no socket at ~/.balcony/pty.sock)\n", stderr)
}

// Set initial PTY size to match the local Mac terminal.
// When iOS connects it will send its own size, which takes priority.
let (cols, rows) = PTYManager.getWindowSize(fd: STDOUT_FILENO)
PTYManager.setWindowSize(masterFD: pty.masterFD, cols: cols, rows: rows)

/// Once iOS sends a resize, it owns the PTY size — local SIGWINCH is ignored
/// so that resizing the Mac terminal window doesn't break the iOS display.
var remoteControlsResize = false

// Generate a session ID
let sessionId = UUID().uuidString

// Build environment — inherit current env + set TERM
var env = ProcessInfo.processInfo.environment
env["TERM"] = env["TERM"] ?? "xterm-256color"
let envStrings = env.map { "\($0.key)=\($0.value)" }

// Spawn claude in the PTY
let childPID: pid_t
do {
    childPID = try PTYManager.spawnProcess(
        executable: claudePath,
        args: fullArgs,
        slavePath: pty.slavePath,
        env: envStrings
    )
} catch {
    fputs("Error: Failed to spawn claude: \(error)\n", stderr)
    close(pty.masterFD)
    exit(1)
}

// Send session info to Mac agent
if socketConnected {
    let cwd = FileManager.default.currentDirectoryPath
    let info = PTYSessionInfo(
        sessionId: sessionId,
        pid: childPID,
        cwd: cwd,
        args: claudeArgs.joined(separator: " "),
        cols: cols,
        rows: rows
    )
    socketClient.sendSessionInfo(info)
    fputs("[balcony] Session registered: \(sessionId)\n", stderr)
}

// Set up the I/O bridge
let bridge = IOBridge(masterFD: pty.masterFD, childPID: childPID, socketClient: socketConnected ? socketClient : nil)

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

// Handle SIGWINCH — forward terminal resize to PTY and child,
// but only if iOS hasn't taken control of the PTY size.
signal(SIGWINCH) { _ in
    guard !remoteControlsResize else { return }
    let (newCols, newRows) = PTYManager.getWindowSize(fd: STDOUT_FILENO)
    PTYManager.setWindowSize(masterFD: pty.masterFD, cols: newCols, rows: newRows)
    kill(childPID, SIGWINCH)
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

// Enter the GCD main run loop — never returns.
// Exit happens via the process source or PTY EIO fallback calling cleanup().
dispatchMain()
