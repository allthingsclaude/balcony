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

    // Content streaming
    case terminalOutput
    case userInput

    // Tool use events
    case toolUseStart
    case toolUseEnd

    // Presence
    case awayStatusUpdate
}
