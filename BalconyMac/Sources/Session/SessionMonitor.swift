import Foundation
import BalconyShared
import os
import CoreServices

// MARK: - Session Events

/// Events emitted by the session monitor.
public enum SessionEvent: Sendable {
    case sessionDiscovered(Session)
    case sessionUpdated(Session, newMessages: [SessionMessage])
    case sessionEnded(String)
}

// MARK: - SessionMonitor

/// Monitors Claude Code session files via FSEvents.
///
/// Watches `~/.claude/projects/` recursively for JSONL session files,
/// detects new sessions, tails active files, and publishes events.
actor SessionMonitor {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "SessionMonitor")
    private let parser = JSONLParser()

    private var sessions: [String: Session] = [:]
    private var fileOffsets: [String: UInt64] = [:]
    private var filePaths: [String: String] = [:] // sessionId -> filePath
    private var sessionCWDs: [String: String] = [:] // sessionId -> cwd
    private var isMonitoring = false

    private let claudeDir: String
    private var fsWatcher: FSEventsWatcher?
    private var continuation: AsyncStream<SessionEvent>.Continuation?

    init(claudeDir: String = "\(NSHomeDirectory())/.claude") {
        self.claudeDir = claudeDir
    }

    // MARK: - Public API

    /// Start monitoring and return a stream of session events.
    func startMonitoring() -> AsyncStream<SessionEvent> {
        guard !isMonitoring else {
            return AsyncStream { $0.finish() }
        }
        isMonitoring = true

        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        self.continuation = continuation

        let projectsDir = "\(claudeDir)/projects"

        // Ensure the directory exists before watching
        let fm = FileManager.default
        if !fm.fileExists(atPath: projectsDir) {
            try? fm.createDirectory(atPath: projectsDir, withIntermediateDirectories: true)
        }

        // Scan existing sessions
        scanExistingSessions(projectsDir: projectsDir)

        // Set up FSEvents watcher
        let watcher = FSEventsWatcher(path: projectsDir) { [weak self] changedPaths in
            guard let self else { return }
            Task { await self.handleFileSystemEvents(changedPaths) }
        }
        watcher.start()
        self.fsWatcher = watcher

        logger.info("Started monitoring: \(projectsDir)")
        return stream
    }

    /// Stop monitoring.
    func stopMonitoring() {
        isMonitoring = false
        fsWatcher?.stop()
        fsWatcher = nil
        continuation?.finish()
        continuation = nil
        logger.info("Stopped monitoring")
    }

    /// Get all known sessions with refreshed statuses, sorted by last activity.
    func getSessions() -> [Session] {
        refreshSessionStatuses()
        return Array(sessions.values).sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Get a specific session by ID.
    func getSession(id: String) -> Session? {
        sessions[id]
    }

    /// Get the working directory for a session.
    func getCWD(forSession sessionId: String) -> String? {
        sessionCWDs[sessionId]
    }

    /// Read all messages from a session's JSONL file (for sending history to new subscribers).
    func getSessionHistory(id sessionId: String) -> [SessionMessage] {
        guard let filePath = filePaths[sessionId] else { return [] }
        guard let data = FileManager.default.contents(atPath: filePath) else { return [] }
        return parser.parse(data)
    }

    /// Mark a session as ended.
    func endSession(id: String) {
        guard var session = sessions[id] else { return }
        session.status = .completed
        sessions[id] = session
        continuation?.yield(.sessionEnded(id))
        logger.info("Session ended: \(id)")
    }

    // MARK: - Directory Scanning

    private func scanExistingSessions(projectsDir: String) {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return }

        for projectHash in projectDirs {
            // Session JSONL files live directly inside the project hash directory:
            // ~/.claude/projects/{hash}/{session-id}.jsonl
            let projectDir = "\(projectsDir)/\(projectHash)"
            guard let files = try? fm.contentsOfDirectory(atPath: projectDir) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let sessionId = String(file.dropLast(6))
                let filePath = "\(projectDir)/\(file)"
                processSessionFile(sessionId: sessionId, projectPath: projectHash, filePath: filePath)
            }
        }
    }

    // MARK: - FSEvents Handling

    private func handleFileSystemEvents(_ changedPaths: [String]) {
        for path in changedPaths {
            guard path.hasSuffix(".jsonl") else { continue }

            // Extract session ID and project hash from path
            // Format: .../projects/{hash}/{id}.jsonl
            let components = path.components(separatedBy: "/")
            guard let projectsIdx = components.lastIndex(of: "projects"),
                  components.count > projectsIdx + 2,
                  let fileName = components.last else { continue }

            let projectHash = components[projectsIdx + 1]
            let sessionId = String(fileName.dropLast(6))

            processSessionFile(sessionId: sessionId, projectPath: projectHash, filePath: path)
        }
    }

    // MARK: - Status Detection

    /// How recently a file must be modified to be considered active.
    private let activeThreshold: TimeInterval = 120 // 2 minutes

    /// Infer session status from its JSONL file modification time.
    private func inferStatus(filePath: String) -> SessionStatus {
        guard let modDate = fileModificationDate(filePath) else { return .completed }
        let age = Date().timeIntervalSince(modDate)
        if age < activeThreshold {
            return .active
        } else {
            return .completed
        }
    }

    /// Refresh statuses for all tracked sessions based on file modification times.
    private func refreshSessionStatuses() {
        for (sessionId, filePath) in filePaths {
            guard var session = sessions[sessionId] else { continue }
            let newStatus = inferStatus(filePath: filePath)
            if session.status != newStatus {
                session.status = newStatus
                // Update lastActivityAt from file modification time
                if let modDate = fileModificationDate(filePath) {
                    session.lastActivityAt = modDate
                }
                sessions[sessionId] = session
            }
        }
    }

    // MARK: - File Processing

    private func processSessionFile(sessionId: String, projectPath: String, filePath: String) {
        let isNew = sessions[sessionId] == nil
        let status = inferStatus(filePath: filePath)
        let modDate = fileModificationDate(filePath)

        if isNew {
            let session = Session(
                id: sessionId,
                projectPath: projectPath,
                status: status,
                createdAt: fileCreationDate(filePath) ?? Date(),
                lastActivityAt: modDate ?? Date()
            )
            sessions[sessionId] = session
            filePaths[sessionId] = filePath
            continuation?.yield(.sessionDiscovered(session))
            logger.info("Discovered session: \(sessionId) (status: \(status.rawValue))")
        }

        // Read new content since last offset
        let messages = readNewContent(sessionId: sessionId, filePath: filePath)
        if !messages.isEmpty, var session = sessions[sessionId] {
            session.lastActivityAt = messages.last?.timestamp ?? Date()
            session.messageCount += messages.count
            session.status = .active // file is being written to right now
            sessions[sessionId] = session
            continuation?.yield(.sessionUpdated(session, newMessages: messages))
        }
    }

    private func readNewContent(sessionId: String, filePath: String) -> [SessionMessage] {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else { return [] }
        defer { try? fileHandle.close() }

        let offset = fileOffsets[sessionId] ?? 0
        fileHandle.seek(toFileOffset: offset)

        let newData = fileHandle.readDataToEndOfFile()
        guard !newData.isEmpty else { return [] }

        fileOffsets[sessionId] = offset + UInt64(newData.count)

        guard let text = String(data: newData, encoding: .utf8) else { return [] }
        let entries = parser.parseEntries(text)

        // Extract CWD from entries (use the latest non-nil cwd)
        for entry in entries {
            if let cwd = entry.cwd {
                sessionCWDs[sessionId] = cwd
                if var session = sessions[sessionId] {
                    session.cwd = cwd
                    sessions[sessionId] = session
                }
            }
        }

        return entries.compactMap { $0.message }
    }

    private func fileCreationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date
    }

    private func fileModificationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}

// MARK: - FSEvents Wrapper

/// Wraps the CoreServices FSEvents C API for recursive directory monitoring.
private final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "com.balcony.fsevents", qos: .utility)

    init(path: String, callback: @escaping @Sendable ([String]) -> Void) {
        self.path = path
        self.callback = callback
    }

    func start() {
        let pathCF = path as CFString
        let pathsToWatch = [pathCF] as CFArray

        // Wrap self in context so the C callback can reach us
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // 300ms latency for near-real-time tailing
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handleEvents(_ paths: [String]) {
        callback(paths)
    }
}

/// C callback bridging FSEvents to the Swift wrapper.
private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()

    let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var paths: [String] = []
    for i in 0..<numEvents {
        if let cfPath = CFArrayGetValueAtIndex(cfArray, i) {
            let nsPath = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
            paths.append(nsPath)
        }
    }

    watcher.handleEvents(paths)
}
