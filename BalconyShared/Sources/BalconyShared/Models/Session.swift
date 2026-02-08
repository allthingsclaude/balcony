import Foundation

/// Represents a Claude Code session running on the Mac.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectPath: String
    public var status: SessionStatus
    public let createdAt: Date
    public var lastActivityAt: Date
    public var messageCount: Int
    public var cwd: String?
    public var cols: UInt16?
    public var rows: UInt16?

    public var projectName: String {
        (projectPath as NSString).lastPathComponent
    }

    public init(
        id: String,
        projectPath: String,
        status: SessionStatus = .active,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        messageCount: Int = 0,
        cwd: String? = nil,
        cols: UInt16? = nil,
        rows: UInt16? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.status = status
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.messageCount = messageCount
        self.cwd = cwd
        self.cols = cols
        self.rows = rows
    }
}

/// Status of a Claude Code session.
public enum SessionStatus: String, Codable, Sendable {
    case active
    case idle
    case completed
    case error
}
