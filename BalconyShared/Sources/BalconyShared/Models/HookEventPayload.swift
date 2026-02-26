import Foundation

/// Payload for forwarding hook events from Mac to iOS via WebSocket.
public struct HookEventPayload: Codable, Sendable {
    /// The PTY session ID this hook event belongs to.
    public let sessionId: String

    /// The tool requesting permission.
    public let toolName: String

    /// The command text for Bash tools.
    public let command: String?

    /// The file path for file operation tools.
    public let filePath: String?

    /// Risk level as a string for cross-platform transport.
    public let riskLevel: String

    /// When the hook event was received.
    public let timestamp: Date

    public init(sessionId: String, toolName: String, command: String?, filePath: String?, riskLevel: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.riskLevel = riskLevel
        self.timestamp = timestamp
    }

    /// Create from a PermissionPromptInfo.
    public init(from info: PermissionPromptInfo) {
        self.sessionId = info.sessionId
        self.toolName = info.toolName
        self.command = info.command
        self.filePath = info.filePath
        self.riskLevel = info.riskLevel.rawValue
        self.timestamp = info.timestamp
    }
}

/// Payload for forwarding idle prompt events (Claude waiting for input) from Mac to iOS.
public struct IdlePromptPayload: Codable, Sendable {
    /// The PTY session ID.
    public let sessionId: String

    /// Claude's last assistant message (the question or summary).
    public let lastAssistantMessage: String

    /// When the idle prompt was detected.
    public let timestamp: Date

    public init(sessionId: String, lastAssistantMessage: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.lastAssistantMessage = lastAssistantMessage
        self.timestamp = timestamp
    }

    /// Create from an IdlePromptInfo.
    public init(from info: IdlePromptInfo) {
        self.sessionId = info.sessionId
        self.lastAssistantMessage = info.lastAssistantMessage
        self.timestamp = info.timestamp
    }
}

/// Payload for dismissing a hook event prompt on iOS.
public struct HookDismissPayload: Codable, Sendable {
    /// The PTY session ID whose prompt was answered.
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}
