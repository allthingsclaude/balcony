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

    /// Get all known sessions sorted by last activity.
    func getSessions() -> [Session] {
        Array(sessions.values).sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Get a specific session by ID.
    func getSession(id: String) -> Session? {
        sessions[id]
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
            let sessionsDir = "\(projectsDir)/\(projectHash)/sessions"
            guard let sessionFiles = try? fm.contentsOfDirectory(atPath: sessionsDir) else { continue }

            for file in sessionFiles where file.hasSuffix(".jsonl") {
                let sessionId = String(file.dropLast(6))
                let filePath = "\(sessionsDir)/\(file)"
                processSessionFile(sessionId: sessionId, projectPath: projectHash, filePath: filePath)
            }
        }
    }

    // MARK: - FSEvents Handling

    private func handleFileSystemEvents(_ changedPaths: [String]) {
        for path in changedPaths {
            guard path.hasSuffix(".jsonl") else { continue }

            // Extract session ID and project hash from path
            // Format: .../projects/{hash}/sessions/{id}.jsonl
            let components = path.components(separatedBy: "/")
            guard let sessionsIdx = components.lastIndex(of: "sessions"),
                  sessionsIdx > 0,
                  let fileName = components.last else { continue }

            let sessionId = String(fileName.dropLast(6))
            let projectHash = components[sessionsIdx - 1]

            processSessionFile(sessionId: sessionId, projectPath: projectHash, filePath: path)
        }
    }

    // MARK: - File Processing

    private func processSessionFile(sessionId: String, projectPath: String, filePath: String) {
        let isNew = sessions[sessionId] == nil

        if isNew {
            let session = Session(
                id: sessionId,
                projectPath: projectPath,
                status: .active,
                createdAt: fileCreationDate(filePath) ?? Date()
            )
            sessions[sessionId] = session
            filePaths[sessionId] = filePath
            continuation?.yield(.sessionDiscovered(session))
            logger.info("Discovered session: \(sessionId)")
        }

        // Read new content since last offset
        let messages = readNewContent(sessionId: sessionId, filePath: filePath)
        if !messages.isEmpty, var session = sessions[sessionId] {
            session.lastActivityAt = messages.last?.timestamp ?? Date()
            session.messageCount += messages.count

            // Infer status from latest message
            if let last = messages.last {
                switch last.role {
                case .human:
                    session.status = .active
                case .assistant:
                    session.status = .active
                case .toolUse:
                    session.status = .active
                case .toolResult:
                    session.status = .active
                case .system:
                    session.status = .active
                }
            }

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
        return parser.parse(newData)
    }

    private func fileCreationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date
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
