import XCTest
@testable import BalconyShared

final class CryptoManagerTests: XCTestCase {

    func testKeyPairGeneration() async throws {
        let crypto = CryptoManager()
        let keyPair = try await crypto.generateKeyPair()

        XCTAssertFalse(keyPair.publicKey.isEmpty)
        XCTAssertFalse(keyPair.secretKey.isEmpty)
    }

    func testPublicKeyBase64() async throws {
        let crypto = CryptoManager()
        _ = try await crypto.generateKeyPair()
        let base64 = try await crypto.publicKeyBase64()

        XCTAssertFalse(base64.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: base64))
    }

    func testEncryptDecryptRoundTrip() async throws {
        // Simulate two devices
        let alice = CryptoManager()
        let bob = CryptoManager()

        let aliceKP = try await alice.generateKeyPair()
        let bobKP = try await bob.generateKeyPair()

        // Key exchange
        try await alice.deriveSharedSecret(theirPublicKey: bobKP.publicKey)
        try await bob.deriveSharedSecret(theirPublicKey: aliceKP.publicKey)

        // Encrypt on Alice's side
        let plaintext = "Hello from Alice!".data(using: .utf8)!
        let ciphertext = try await alice.encrypt(plaintext)

        // Decrypt on Bob's side
        let decrypted = try await bob.decrypt(ciphertext)

        XCTAssertEqual(String(data: decrypted, encoding: .utf8), "Hello from Alice!")
    }
}
