import Foundation
import Crypto
import X509
import SwiftASN1
import NIOSSL

/// Generates and pins the self-signed TLS identity that secures the iPhone↔Mac WebSocket link.
///
/// The Mac runs the WebSocket server over TLS (`wss://`) using a long-lived self-signed
/// certificate. Because the iOS client dials the Mac by raw IP address (the Bonjour endpoint is
/// resolved to an IP before connecting), there is no usable hostname/SAN to validate against and
/// no CA chain — so the client authenticates the server **solely** by pinning the certificate.
///
/// The pin is the SHA-256 of the certificate's DER encoding, base64-encoded. It is carried in the
/// pairing QR code, which is the trust anchor: an active on-path attacker cannot present a
/// certificate with the same DER without the matching private key. This is what closes the
/// man-in-the-middle hole that the previous (unauthenticated) key-exchange handshake left open.
public enum TLSIdentity {

    // MARK: - Generation

    /// Generate a fresh self-signed P-256 certificate and private key, PEM-encoded.
    ///
    /// Generated once on the Mac and persisted in the Keychain; regenerating would invalidate
    /// every previously paired client's pin.
    public static func generateSelfSigned() throws -> (certPEM: String, keyPEM: String) {
        let key = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(key)

        let name = try DistinguishedName {
            CommonName("Balcony")
        }

        let now = Date()
        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: certKey.publicKey,
            // Backdate slightly so a small clock skew between devices doesn't reject a fresh cert.
            notValidBefore: now.addingTimeInterval(-60 * 60),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(
                    BasicConstraints.notCertificateAuthority
                )
                SubjectAlternativeNames([.dnsName("balcony.local")])
            },
            issuerPrivateKey: certKey
        )

        let certPEM = try cert.serializeAsPEM().pemString
        let keyPEM = key.pemRepresentation
        return (certPEM, keyPEM)
    }

    // MARK: - Server context

    /// Build a NIOSSL server context from a PEM certificate + private key.
    public static func makeServerContext(certPEM: String, keyPEM: String) throws -> NIOSSLContext {
        do {
            let cert = try NIOSSLCertificate(bytes: Array(certPEM.utf8), format: .pem)
            let key = try NIOSSLPrivateKey(bytes: Array(keyPEM.utf8), format: .pem)
            let config = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
            return try NIOSSLContext(configuration: config)
        } catch {
            throw BalconyError.cryptoError("Failed to build TLS server context: \(error)")
        }
    }

    // MARK: - Pinning

    /// The pin for a certificate given its DER bytes: SHA-256 of the DER, base64-encoded.
    ///
    /// This is the canonical definition shared by both peers — the iOS client computes the same
    /// value over the leaf certificate it receives on the wire (`SecCertificateCopyData`).
    public static func pin(forCertDER der: [UInt8]) -> String {
        let digest = SHA256.hash(data: Data(der))
        return Data(digest).base64EncodedString()
    }

    /// The pin for a PEM certificate. Decodes to DER via NIOSSL so the bytes match exactly what
    /// the server will present on the wire.
    public static func pin(forCertPEM pem: String) throws -> String {
        do {
            let cert = try NIOSSLCertificate(bytes: Array(pem.utf8), format: .pem)
            return pin(forCertDER: try cert.toDERBytes())
        } catch {
            throw BalconyError.cryptoError("Failed to compute certificate pin: \(error)")
        }
    }
}
