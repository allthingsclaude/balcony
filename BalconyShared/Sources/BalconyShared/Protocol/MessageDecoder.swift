import Foundation

/// Decodes BalconyMessage instances from WebSocket data.
public struct MessageDecoder: Sendable {
    private let jsonDecoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
    }

    /// Decode a message from JSON data.
    public func decode(_ data: Data) throws -> BalconyMessage {
        try jsonDecoder.decode(BalconyMessage.self, from: data)
    }

    /// Decode a message from a UTF-8 string.
    public func decode(_ string: String) throws -> BalconyMessage {
        guard let data = string.data(using: .utf8) else {
            throw BalconyError.decodingFailed("Failed to convert string to UTF-8 data")
        }
        return try decode(data)
    }
}
