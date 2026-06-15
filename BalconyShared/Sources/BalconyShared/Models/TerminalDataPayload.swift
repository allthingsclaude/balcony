import Foundation

/// Payload for raw PTY terminal data (binary terminal bytes).
public struct TerminalDataPayload: Codable, Sendable {
    public let sessionId: String
    /// Raw terminal bytes, base64-encoded for JSON transport.
    public let data: Data
    /// The highest user-input sequence the Mac had applied when it sent this
    /// chunk. Lets the phone tell whether the terminal reflects all the input
    /// it has sent (so it can safely adopt the Mac's input box). Optional for
    /// wire compatibility with peers that don't send it.
    public let inputSeq: UInt64?

    public init(sessionId: String, data: Data, inputSeq: UInt64? = nil) {
        self.sessionId = sessionId
        self.data = data
        self.inputSeq = inputSeq
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
