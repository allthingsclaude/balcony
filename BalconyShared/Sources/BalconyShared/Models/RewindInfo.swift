import Foundation

/// Information about a single conversation turn for the rewind picker.
public struct RewindTurnInfo: Codable, Sendable, Identifiable {
    /// Turn number (1 = most recent).
    public let id: Int

    /// Role of this turn ("user" or "assistant").
    public let role: String

    /// First ~80 characters of the turn's text content.
    public let preview: String

    public init(id: Int, role: String, preview: String) {
        self.id = id
        self.role = role
        self.preview = preview
    }
}

/// Payload sent from iOS to Mac when user selects a rewind point.
public struct RewindSelectionPayload: Codable, Sendable {
    /// How many turns to rewind.
    public let turnCount: Int

    /// The PTY session ID to send the rewind command to.
    public let ptySessionId: String

    public init(turnCount: Int, ptySessionId: String) {
        self.turnCount = turnCount
        self.ptySessionId = ptySessionId
    }
}
