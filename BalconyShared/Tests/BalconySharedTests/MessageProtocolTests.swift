import XCTest
@testable import BalconyShared

final class MessageProtocolTests: XCTestCase {

    func testMessageEncodeDecode() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let session = Session(id: "s1", projectPath: "/test")
        let message = try BalconyMessage.create(type: .sessionUpdate, payload: session)

        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.type, .sessionUpdate)
        XCTAssertEqual(decoded.id, message.id)

        let decodedSession = try decoded.decodePayload(Session.self)
        XCTAssertEqual(decodedSession.id, "s1")
    }

    func testMessageStringRoundTrip() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let payload = "test".data(using: .utf8)!
        let message = BalconyMessage(type: .ping, payload: payload)

        let string = try encoder.encodeToString(message)
        let decoded = try decoder.decode(string)

        XCTAssertEqual(decoded.type, .ping)
    }
}
