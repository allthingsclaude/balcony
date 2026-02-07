import Foundation
import Sodium

/// An X25519 key pair for E2E encryption.
public struct KeyPair: Sendable {
    public let publicKey: Bytes
    public let secretKey: Bytes

    public init(publicKey: Bytes, secretKey: Bytes) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }

    /// SHA256 fingerprint of the public key (first 8 bytes, hex-encoded).
    public var fingerprint: String {
        let data = Data(publicKey)
        // Simple hash for fingerprint display
        var hash: UInt64 = 0
        for byte in data {
            hash = hash &* 31 &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
