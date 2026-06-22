import XCTest
import NIOSSL
@testable import BalconyShared

final class TLSIdentityTests: XCTestCase {

    func testGeneratedCertBuildsServerContext() throws {
        let identity = try TLSIdentity.generateSelfSigned()
        // Should not throw: the generated PEM cert + key feed into a usable NIOSSL server context.
        _ = try TLSIdentity.makeServerContext(certPEM: identity.certPEM, keyPEM: identity.keyPEM)
    }

    func testPinFromPEMMatchesPinFromDER() throws {
        let identity = try TLSIdentity.generateSelfSigned()

        let pinFromPEM = try TLSIdentity.pin(forCertPEM: identity.certPEM)

        // Recompute the pin from the DER directly and confirm both code paths agree — this is the
        // cross-consistency guarantee for Mac (PEM) vs iOS (leaf DER off the wire).
        let der = try NIOSSLCertificate(bytes: Array(identity.certPEM.utf8), format: .pem).toDERBytes()
        let pinFromDER = TLSIdentity.pin(forCertDER: der)

        XCTAssertEqual(pinFromPEM, pinFromDER)
        XCTAssertFalse(pinFromPEM.isEmpty)
    }

    func testPinIsStableAcrossReads() throws {
        let identity = try TLSIdentity.generateSelfSigned()
        let pin1 = try TLSIdentity.pin(forCertPEM: identity.certPEM)
        let pin2 = try TLSIdentity.pin(forCertPEM: identity.certPEM)
        XCTAssertEqual(pin1, pin2)
    }

    func testDistinctCertsProduceDistinctPins() throws {
        let a = try TLSIdentity.generateSelfSigned()
        let b = try TLSIdentity.generateSelfSigned()
        let pinA = try TLSIdentity.pin(forCertPEM: a.certPEM)
        let pinB = try TLSIdentity.pin(forCertPEM: b.certPEM)
        XCTAssertNotEqual(pinA, pinB)
    }
}
