import Foundation
import CryptoKit
import Sodium

/// An X25519 key pair for E2E encryption.
public struct KeyPair: Sendable {
    public let publicKey: Bytes
    public let secretKey: Bytes

    public init(publicKey: Bytes, secretKey: Bytes) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }

    /// SHA-256 fingerprint of the public key (first 8 bytes, hex-encoded).
    ///
    /// Used for display and device identity. A real cryptographic digest (rather than a
    /// rolling hash) so it is safe to pin against once handshake-key verification lands.
    public var fingerprint: String {
        let digest = SHA256.hash(data: Data(publicKey))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
