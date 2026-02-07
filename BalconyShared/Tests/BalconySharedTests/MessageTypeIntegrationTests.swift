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

    func testSessionUpdateMessage() throws {
        let session = Session(
            id: "sess-99",
            projectPath: "/Users/dev/big-project",
            status: .waitingForInput,
            messageCount: 15
        )
        let msg = try BalconyMessage.create(type: .sessionUpdate, payload: session)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .sessionUpdate)
        let result = try decoded.decodePayload(Session.self)
        XCTAssertEqual(result.status, .waitingForInput)
        XCTAssertEqual(result.projectName, "big-project")
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

    func testTerminalOutputMessage() throws {
        let output = "\u{1B}[32m✓\u{1B}[0m All tests passed (42 assertions)\n"
        let msg = try BalconyMessage.create(type: .terminalOutput, payload: output)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .terminalOutput)
        XCTAssertEqual(try decoded.decodePayload(String.self), output)
    }

    func testUserInputMessage() throws {
        let input = "yes, go ahead and commit"
        let msg = try BalconyMessage.create(type: .userInput, payload: input)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .userInput)
        XCTAssertEqual(try decoded.decodePayload(String.self), input)
    }

    // MARK: - Tool Use Messages

    func testToolUseStartMessage() throws {
        let toolUse = ToolUse(
            toolName: "Edit",
            input: "{\"file\": \"src/main.swift\", \"changes\": \"...\"}",
            status: .running
        )
        let msg = try BalconyMessage.create(type: .toolUseStart, payload: toolUse)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .toolUseStart)
        let result = try decoded.decodePayload(ToolUse.self)
        XCTAssertEqual(result.toolName, "Edit")
        XCTAssertEqual(result.status, .running)
        XCTAssertNil(result.output)
    }

    func testToolUseEndMessage() throws {
        let toolUse = ToolUse(
            toolName: "Bash",
            input: "swift build",
            output: "Build complete! (0.42s)",
            status: .completed,
            completedAt: Date()
        )
        let msg = try BalconyMessage.create(type: .toolUseEnd, payload: toolUse)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .toolUseEnd)
        let result = try decoded.decodePayload(ToolUse.self)
        XCTAssertEqual(result.toolName, "Bash")
        XCTAssertEqual(result.output, "Build complete! (0.42s)")
        XCTAssertEqual(result.status, .completed)
        XCTAssertNotNil(result.completedAt)
    }

    // MARK: - Presence Messages

    func testAwayStatusUpdateMessage() throws {
        let signals = AwaySignals(
            bleRSSI: -45,
            idleSeconds: 30,
            screenLocked: false,
            onLocalNetwork: true
        )
        let msg = try BalconyMessage.create(type: .awayStatusUpdate, payload: signals)
        let decoded = try decoder.decode(try encoder.encode(msg))

        XCTAssertEqual(decoded.type, .awayStatusUpdate)
        let result = try decoded.decodePayload(AwaySignals.self)
        XCTAssertEqual(result.computeStatus(), .present)
        XCTAssertEqual(result.bleRSSI, -45)
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
    func testAllTypesViaStringEncoding() throws {
        let allTypes: [MessageType] = [
            .handshake, .handshakeAck, .ping, .pong, .error,
            .sessionList, .sessionUpdate, .sessionSubscribe, .sessionUnsubscribe,
            .terminalOutput, .userInput,
            .toolUseStart, .toolUseEnd,
            .awayStatusUpdate,
        ]

        for type in allTypes {
            let payload = "test".data(using: .utf8)!
            let msg = BalconyMessage(type: type, payload: payload)
            let string = try encoder.encodeToString(msg)
            let decoded = try decoder.decode(string)
            XCTAssertEqual(decoded.type, type, "String round-trip failed for type: \(type)")
        }
    }

    /// Every MessageType must survive data-based encode/decode.
    func testAllTypesViaDataEncoding() throws {
        let allTypes: [MessageType] = [
            .handshake, .handshakeAck, .ping, .pong, .error,
            .sessionList, .sessionUpdate, .sessionSubscribe, .sessionUnsubscribe,
            .terminalOutput, .userInput,
            .toolUseStart, .toolUseEnd,
            .awayStatusUpdate,
        ]

        for type in allTypes {
            let payload = "test".data(using: .utf8)!
            let msg = BalconyMessage(type: type, payload: payload)
            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(data)
            XCTAssertEqual(decoded.type, type, "Data round-trip failed for type: \(type)")
            XCTAssertEqual(decoded.id, msg.id, "UUID mismatch for type: \(type)")
        }
    }
}
