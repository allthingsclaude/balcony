import Foundation

/// Encodes BalconyMessage instances for WebSocket transmission.
public struct MessageEncoder: Sendable {
    private let jsonEncoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [] // compact JSON
        self.jsonEncoder = encoder
    }

    /// Encode a message to JSON data.
    public func encode(_ message: BalconyMessage) throws -> Data {
        try jsonEncoder.encode(message)
    }

    /// Encode a message to a UTF-8 string.
    public func encodeToString(_ message: BalconyMessage) throws -> String {
        let data = try encode(message)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BalconyError.encodingFailed("Failed to convert message data to UTF-8 string")
        }
        return string
    }
}
