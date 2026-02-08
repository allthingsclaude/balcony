import Foundation

/// A single message within a Claude Code session.
public struct SessionMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public var toolUses: [ToolUse]

    public init(
        id: UUID = UUID(),
        sessionId: String,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolUses: [ToolUse] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolUses = toolUses
    }
}

/// The role of a message sender.
public enum MessageRole: String, Codable, Sendable {
    case human
    case user
    case assistant
    case system
    case toolUse = "tool_use"
    case toolResult = "tool_result"
}
