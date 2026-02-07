import Foundation
import BalconyShared
import os

/// Monitors Claude Code session files via FSEvents.
actor SessionMonitor {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "SessionMonitor")
    private let parser = JSONLParser()

    private var sessions: [String: Session] = [:]
    private var fileOffsets: [String: UInt64] = [:]
    private var isMonitoring = false

    private let claudeDir: String

    init(claudeDir: String = "\(NSHomeDirectory())/.claude") {
        self.claudeDir = claudeDir
    }

    // MARK: - Public API

    /// Start monitoring Claude Code session directory.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Started monitoring: \(self.claudeDir)")
        // TODO: Set up FSEvents or DispatchSource for directory monitoring
        // TODO: Scan existing session files
    }

    /// Stop monitoring.
    func stopMonitoring() {
        isMonitoring = false
        logger.info("Stopped monitoring")
    }

    /// Get all known sessions.
    func getSessions() -> [Session] {
        Array(sessions.values).sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Read new content from a session file.
    func readNewContent(sessionId: String, filePath: String) -> [SessionMessage] {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return []
        }

        let offset = fileOffsets[sessionId] ?? 0
        guard UInt64(data.count) > offset else { return [] }

        let newData = data.subdata(in: Int(offset)..<data.count)
        fileOffsets[sessionId] = UInt64(data.count)

        return parser.parse(newData)
    }
}
