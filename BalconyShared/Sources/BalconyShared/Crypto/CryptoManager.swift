import Foundation
import Sodium

/// Manages E2E encryption using X25519 key exchange and XChaCha20-Poly1305.
public actor CryptoManager {
    private let sodium = Sodium()
    private var keyPair: KeyPair?
    private var sharedSecret: Bytes?
    private var nonceCounter: UInt64 = 0

    public init() {}

    // MARK: - Key Generation

    /// Generate a new X25519 key pair for this device.
    public func generateKeyPair() throws -> KeyPair {
        guard let kp = sodium.box.keyPair() else {
            throw BalconyError.cryptoError("Failed to generate key pair")
        }
        let pair = KeyPair(publicKey: kp.publicKey, secretKey: kp.secretKey)
        self.keyPair = pair
        return pair
    }

    /// Get the public key as Base64 for QR code display.
    public func publicKeyBase64() throws -> String {
        guard let kp = keyPair else {
            throw BalconyError.cryptoError("No key pair generated")
        }
        return Data(kp.publicKey).base64EncodedString()
    }

    // MARK: - Key Exchange

    /// Derive shared secret from our private key and their public key.
    public func deriveSharedSecret(theirPublicKey: Bytes) throws {
        guard let kp = keyPair else {
            throw BalconyError.cryptoError("No key pair generated")
        }
        guard let secret = sodium.box.beforenm(
            recipientPublicKey: theirPublicKey,
            senderSecretKey: kp.secretKey
        ) else {
            throw BalconyError.cryptoError("Failed to derive shared secret")
        }
        self.sharedSecret = secret
    }

    // MARK: - Encryption / Decryption

    /// Encrypt plaintext data using XChaCha20-Poly1305.
    public func encrypt(_ plaintext: Data) throws -> Data {
        guard let secret = sharedSecret else {
            throw BalconyError.cryptoError("No shared secret established")
        }

        let nonce = generateNonce()
        guard let ciphertext = sodium.secretBox.seal(
            message: Bytes(plaintext),
            secretKey: secret,
            nonce: nonce
        ) else {
            throw BalconyError.cryptoError("Encryption failed")
        }

        // Prepend nonce to ciphertext
        return Data(nonce + ciphertext)
    }

    /// Decrypt ciphertext data using XChaCha20-Poly1305.
    public func decrypt(_ data: Data) throws -> Data {
        guard let secret = sharedSecret else {
            throw BalconyError.cryptoError("No shared secret established")
        }

        let bytes = Bytes(data)
        let nonceSize = sodium.secretBox.NonceBytes
        guard bytes.count > nonceSize else {
            throw BalconyError.cryptoError("Data too short to contain nonce")
        }

        let nonce = Array(bytes[0..<nonceSize])
        let ciphertext = Array(bytes[nonceSize...])

        guard let plaintext = sodium.secretBox.open(
            authenticatedCipherText: ciphertext,
            secretKey: secret,
            nonce: nonce
        ) else {
            throw BalconyError.cryptoError("Decryption failed - invalid ciphertext or wrong key")
        }

        return Data(plaintext)
    }

    // MARK: - Private

    private func generateNonce() -> Bytes {
        nonceCounter += 1
        var nonce = Bytes(repeating: 0, count: sodium.secretBox.NonceBytes)
        var counter = nonceCounter
        for i in 0..<8 {
            nonce[i] = UInt8(counter & 0xFF)
            counter >>= 8
        }
        return nonce
    }
}
