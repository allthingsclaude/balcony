import Foundation

/// Payload for raw PTY terminal data (binary terminal bytes).
public struct TerminalDataPayload: Codable, Sendable {
    public let sessionId: String
    /// Raw terminal bytes, base64-encoded for JSON transport.
    public let data: Data

    public init(sessionId: String, data: Data) {
        self.sessionId = sessionId
        self.data = data
    }
}

/// Payload for terminal resize events.
public struct TerminalResizePayload: Codable, Sendable {
    public let sessionId: String
    public let cols: UInt16
    public let rows: UInt16

    public init(sessionId: String, cols: UInt16, rows: UInt16) {
        self.sessionId = sessionId
        self.cols = cols
        self.rows = rows
    }
}
