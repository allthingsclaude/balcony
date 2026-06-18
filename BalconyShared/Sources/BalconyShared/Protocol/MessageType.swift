import Foundation

/// All possible message types in the Balcony WebSocket protocol.
public enum MessageType: String, Codable, Sendable, CaseIterable {
    // Connection lifecycle
    case handshake
    case handshakeAck
    case ping
    case pong
    /// Protocol-level error reporting. Emitted by the Mac server on handshake/auth failure
    /// (see `WebSocketServer.sendError`); the iOS client surfaces it during the handshake.
    case error

    // Session management
    case sessionList
    case sessionSubscribe
    case sessionUnsubscribe

    // PTY terminal streaming
    case terminalData
    case terminalResize
    case userInput

    // Structured transcript (parsed from the session JSONL) — the reliable
    // source of truth for settled messages, complementing the PTY stream.
    case transcriptEvents

    // Slash commands
    case slashCommands

    // File list for @ picker
    case fileList

    // Session picker (native UI for /resume)
    case sessionPickerRequest
    case sessionPickerShow
    case sessionPickerSelection

    // Model picker (native UI for /model)
    case modelPickerRequest
    case modelPickerShow
    case modelPickerSelection

    // Rewind picker (native UI for /rewind)
    case rewindSelection

    // Presence
    case bleRSSIReport

    // Hook events (permission prompts routed from Claude Code hooks)
    case hookEvent
    case hookDismiss

    // Idle prompt (Claude stopped and is waiting for user input)
    case idlePrompt
    case idlePromptDismiss

    // AskUserQuestion (structured multi-option questions from Claude)
    case askUserQuestion
    case askUserQuestionDismiss
    case askUserQuestionResponse
}
