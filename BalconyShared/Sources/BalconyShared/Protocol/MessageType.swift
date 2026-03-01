import Foundation

/// All possible message types in the Balcony WebSocket protocol.
public enum MessageType: String, Codable, Sendable {
    // Connection lifecycle
    case handshake
    case handshakeAck
    case ping
    case pong
    case error

    // Session management
    case sessionList
    case sessionUpdate
    case sessionSubscribe
    case sessionUnsubscribe

    // PTY terminal streaming
    case terminalData
    case terminalResize
    case userInput

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
    case awayStatusUpdate

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
