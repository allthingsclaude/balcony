import XCTest
@testable import BalconyShared

final class MessageTypeIntegrationTests: XCTestCase {

    let encoder = MessageEncoder()
    let decoder = MessageDecoder()

    // MARK: - Session Messages

    func testSessionListMessage() throws {
        let sessions = [
            Session(id: "s1", projectPath: "/Users/dev/project-a", status: .active, messageCount: 42),
            Session(id: "s2", projectPath: "/Users/dev/project-b", status: .idle, messageCount: 7),
            Session(id: "s3", projectPath: "/Users/dev/project-c", status: .completed, messageCount: 100),
        ]
        let msg = try BalconyMessage.create(type: .sessionList, payload: sessions)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .sessionList)
        let result = try decoded.decodePayload([Session].self)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].projectName, "project-a")
        XCTAssertEqual(result[1].status, .idle)
        XCTAssertEqual(result[2].messageCount, 100)
    }

    func testSessionSubscribeMessage() throws {
        let payload = ["sessionId": "sess-42"]
        let msg = try BalconyMessage.create(type: .sessionSubscribe, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .sessionSubscribe)
        let result = try decoded.decodePayload([String: String].self)
        XCTAssertEqual(result["sessionId"], "sess-42")
    }

    func testSessionUnsubscribeMessage() throws {
        let payload = ["sessionId": "sess-42"]
        let msg = try BalconyMessage.create(type: .sessionUnsubscribe, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .sessionUnsubscribe)
    }

    // MARK: - Content Messages

    func testUserInputMessage() throws {
        let input = "yes, go ahead and commit"
        let msg = try BalconyMessage.create(type: .userInput, payload: input)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .userInput)
        XCTAssertEqual(try decoded.decodePayload(String.self), input)
    }

    func testTerminalDataMessage() throws {
        let payload = TerminalDataPayload(sessionId: "sess-1", data: Data([0x1B, 0x5B, 0x33, 0x32, 0x6D]))
        let msg = try BalconyMessage.create(type: .terminalData, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .terminalData)
        let result = try decoded.decodePayload(TerminalDataPayload.self)
        XCTAssertEqual(result.sessionId, "sess-1")
        XCTAssertEqual(result.data.count, 5)
    }

    func testTerminalResizeMessage() throws {
        let payload = TerminalResizePayload(sessionId: "sess-1", cols: 120, rows: 40)
        let msg = try BalconyMessage.create(type: .terminalResize, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .terminalResize)
        let result = try decoded.decodePayload(TerminalResizePayload.self)
        XCTAssertEqual(result.cols, 120)
        XCTAssertEqual(result.rows, 40)
    }

    // MARK: - Presence Messages

    func testBLERSSIReportMessage() throws {
        let payload = BLERSSIReportPayload(rssi: -52)
        let msg = try BalconyMessage.create(type: .bleRSSIReport, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .bleRSSIReport)
        let result = try decoded.decodePayload(BLERSSIReportPayload.self)
        XCTAssertEqual(result.rssi, -52)
    }

    // MARK: - Connection Messages

    func testHandshakeMessage() throws {
        let device = DeviceInfo(
            id: "mac-001",
            name: "Dev MacBook Pro",
            platform: .macOS,
            publicKeyFingerprint: "a1b2c3d4e5f6g7h8"
        )
        let msg = try BalconyMessage.create(type: .handshake, payload: device)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .handshake)
        let result = try decoded.decodePayload(DeviceInfo.self)
        XCTAssertEqual(result.name, "Dev MacBook Pro")
        XCTAssertEqual(result.platform, .macOS)
    }

    func testHandshakeAckMessage() throws {
        let device = DeviceInfo(
            id: "ios-001",
            name: "Dev iPhone",
            platform: .iOS,
            publicKeyFingerprint: "e5f6g7h8i9j0k1l2"
        )
        let msg = try BalconyMessage.create(type: .handshakeAck, payload: device)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .handshakeAck)
        let result = try decoded.decodePayload(DeviceInfo.self)
        XCTAssertEqual(result.platform, .iOS)
    }

    func testPingMessage() throws {
        let payload = "ping".data(using: .utf8)!
        let msg = BalconyMessage(type: .ping, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))
        XCTAssertEqual(decoded.type, .ping)
    }

    func testPongMessage() throws {
        let payload = "pong".data(using: .utf8)!
        let msg = BalconyMessage(type: .pong, payload: payload)
        let decoded = try decoder.decode(try encoder.encode(msg))
        XCTAssertEqual(decoded.type, .pong)
    }

    func testErrorMessage() throws {
        let errorPayload = ["message": "Session not found: sess-999"]
        let msg = try BalconyMessage.create(type: .error, payload: errorPayload)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .error)
        let result = try decoded.decodePayload([String: String].self)
        XCTAssertEqual(result["message"], "Session not found: sess-999")
    }

    // MARK: - Exhaustive Type Coverage

    /// Every MessageType must survive string-based encode/decode.
    /// Iterates `allCases` so new cases are covered automatically.
    func testAllTypesViaStringEncoding() throws {
        for type in MessageType.allCases {
            let payload = "test".data(using: .utf8)!
            let msg = BalconyMessage(type: type, payload: payload)
            let string = try encoder.encodeToString(msg)
            let decoded = try decoder.decode(string)
            XCTAssertEqual(decoded.type, type, "String round-trip failed for type: \(type)")
        }
    }

    /// Every MessageType must survive data-based encode/decode.
    /// Iterates `allCases` so new cases are covered automatically.
    func testAllTypesViaDataEncoding() throws {
        for type in MessageType.allCases {
            let payload = "test".data(using: .utf8)!
            let msg = BalconyMessage(type: type, payload: payload)
            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(data)
            XCTAssertEqual(decoded.type, type, "Data round-trip failed for type: \(type)")
            XCTAssertEqual(decoded.id, msg.id, "UUID mismatch for type: \(type)")
        }
    }
}
