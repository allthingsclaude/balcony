import Foundation

/// Top-level message envelope for all WebSocket communication.
public struct BalconyMessage: Codable, Sendable {
    public let id: UUID
    public let type: MessageType
    public let timestamp: Date
    public let payload: Data

    public init(
        id: UUID = UUID(),
        type: MessageType,
        timestamp: Date = Date(),
        payload: Data
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }

    /// Create a message with an Encodable payload.
    public static func create<T: Encodable>(
        type: MessageType,
        payload: T
    ) throws -> BalconyMessage {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return BalconyMessage(type: type, payload: data)
    }

    /// Decode the payload into a specific type.
    public func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: payload)
    }
}
