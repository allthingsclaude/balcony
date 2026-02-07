import Foundation

/// Represents a tool invocation by Claude Code.
public struct ToolUse: Codable, Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public let input: String
    public var output: String?
    public var status: ToolUseStatus
    public let startedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        toolName: String,
        input: String,
        output: String? = nil,
        status: ToolUseStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.output = output
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Status of a tool invocation.
public enum ToolUseStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case denied
}
