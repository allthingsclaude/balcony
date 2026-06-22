import Foundation
import BalconyShared
import os

/// Loads — or, on first run, creates and persists — the Mac's long-lived self-signed TLS identity.
///
/// The certificate must be stable across launches: its pin is what every paired iPhone validates,
/// so regenerating it would silently break all existing pairings.
enum ServerTLSIdentity {
    private static let certAccount = "cert-pem"
    private static let keyAccount = "key-pem"
    private static let logger = Logger(subsystem: "com.balcony.mac", category: "ServerTLSIdentity")

    static func loadOrCreate() throws -> (certPEM: String, keyPEM: String) {
        if let cert = KeychainStore.string(forKey: certAccount),
           let key = KeychainStore.string(forKey: keyAccount) {
            return (cert, key)
        }

        let identity = try TLSIdentity.generateSelfSigned()
        let storedCert = KeychainStore.set(identity.certPEM, forKey: certAccount)
        let storedKey = KeychainStore.set(identity.keyPEM, forKey: keyAccount)
        if !storedCert || !storedKey {
            logger.error("Failed to persist TLS identity to Keychain — pairings will break on relaunch")
        }
        return identity
    }
}
