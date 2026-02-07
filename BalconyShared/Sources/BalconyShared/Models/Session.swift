import Foundation

/// Represents a Claude Code session running on the Mac.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectPath: String
    public var status: SessionStatus
    public let createdAt: Date
    public var lastActivityAt: Date
    public var messageCount: Int

    public var projectName: String {
        (projectPath as NSString).lastPathComponent
    }

    public init(
        id: String,
        projectPath: String,
        status: SessionStatus = .active,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        messageCount: Int = 0
    ) {
        self.id = id
        self.projectPath = projectPath
        self.status = status
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.messageCount = messageCount
    }
}

/// Status of a Claude Code session.
public enum SessionStatus: String, Codable, Sendable {
    case active
    case idle
    case waitingForInput
    case completed
    case error
}
