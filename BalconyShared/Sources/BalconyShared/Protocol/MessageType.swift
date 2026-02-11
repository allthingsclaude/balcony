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

    // Presence
    case awayStatusUpdate
}
