import Foundation

/// Domain errors for the Balcony app.
public enum BalconyError: LocalizedError, Sendable {
    case connectionFailed(String)
    case cryptoError(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case sessionNotFound(String)
    case hookError(String)
    case fileSystemError(String)
    case timeout(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .cryptoError(let msg): return "Crypto error: \(msg)"
        case .encodingFailed(let msg): return "Encoding failed: \(msg)"
        case .decodingFailed(let msg): return "Decoding failed: \(msg)"
        case .sessionNotFound(let msg): return "Session not found: \(msg)"
        case .hookError(let msg): return "Hook error: \(msg)"
        case .fileSystemError(let msg): return "File system error: \(msg)"
        case .timeout(let msg): return "Timeout: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
