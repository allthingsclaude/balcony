import XCTest
@testable import BalconyShared

final class SessionParserIntegrationTests: XCTestCase {

    let parser = JSONLParser()

    // MARK: - Realistic Session Parsing

    /// Parse a realistic Claude Code session with multiple message roles.
    func testRealisticSessionParsing() {
        let jsonl = """
        {"type":"human","content":"Fix the bug in UserService.swift","session_id":"sess-001","timestamp":"2024-06-15T10:00:00Z"}
        {"type":"assistant","content":"I'll look at UserService.swift and fix the bug.","session_id":"sess-001","timestamp":"2024-06-15T10:00:02Z"}
        {"type":"tool_use","content":"Reading UserService.swift","session_id":"sess-001","timestamp":"2024-06-15T10:00:03Z"}
        {"type":"tool_result","content":"func fetchUser(id: Int) -> User? { ... }","session_id":"sess-001","timestamp":"2024-06-15T10:00:04Z"}
        {"type":"assistant","content":"I found the issue. The fetchUser method has a race condition.","session_id":"sess-001","timestamp":"2024-06-15T10:00:05Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 5)
        XCTAssertEqual(messages[0].role, .human)
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[2].role, .toolUse)
        XCTAssertEqual(messages[3].role, .toolResult)
        XCTAssertEqual(messages[4].role, .assistant)

        for msg in messages {
            XCTAssertEqual(msg.sessionId, "sess-001")
        }
    }

    // MARK: - Incremental Parsing

    /// Simulate file tailing: parse first batch, then parse appended lines.
    func testIncrementalParsing() {
        let batch1 = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {"type":"assistant","content":"Hi!","session_id":"s1","timestamp":"2024-01-01T00:00:01Z"}
        """
        let messages1 = parser.parse(batch1)
        XCTAssertEqual(messages1.count, 2)

        // New lines appended to file
        let batch2 = """
        {"type":"human","content":"Fix the tests","session_id":"s1","timestamp":"2024-01-01T00:01:00Z"}
        {"type":"assistant","content":"On it!","session_id":"s1","timestamp":"2024-01-01T00:01:01Z"}
        """
        let messages2 = parser.parse(batch2)
        XCTAssertEqual(messages2.count, 2)
        XCTAssertEqual(messages2[0].content, "Fix the tests")
    }

    // MARK: - Incomplete Data

    /// Incomplete trailing line (file still being written) should be skipped.
    func testIncompleteTrailingLine() {
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {"type":"assistant","content":"Work
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .human)
    }

    // MARK: - Multiple Sessions

    /// Parse lines from different sessions independently.
    func testMultipleSessions() {
        let session1 = (0..<5).map { i in
            "{\"type\":\"human\",\"content\":\"Message \(i)\",\"session_id\":\"sess-A\",\"timestamp\":\"2024-01-01T00:00:0\(i)Z\"}"
        }.joined(separator: "\n")

        let session2 = (0..<3).map { i in
            "{\"type\":\"assistant\",\"content\":\"Reply \(i)\",\"session_id\":\"sess-B\",\"timestamp\":\"2024-01-01T00:00:0\(i)Z\"}"
        }.joined(separator: "\n")

        let messages1 = parser.parse(session1)
        let messages2 = parser.parse(session2)

        XCTAssertEqual(messages1.count, 5)
        XCTAssertEqual(messages2.count, 3)

        for msg in messages1 { XCTAssertEqual(msg.sessionId, "sess-A") }
        for msg in messages2 { XCTAssertEqual(msg.sessionId, "sess-B") }
    }

    // MARK: - Content Array Blocks

    /// Claude API format: content is an array of text blocks.
    func testContentArrayBlocks() {
        let jsonl = """
        {"type":"assistant","content":[{"type":"text","text":"First paragraph."},{"type":"text","text":"Second paragraph."}],"session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].content.contains("First paragraph."))
        XCTAssertTrue(messages[0].content.contains("Second paragraph."))
    }

    // MARK: - Special Characters

    /// ANSI escape codes and unicode survive parsing.
    func testSpecialCharactersAndANSI() {
        let jsonl = """
        {"type":"assistant","content":"Output: \\u001B[32m\\u2713\\u001B[0m Tests passed","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(messages[0].content.isEmpty)
    }

    // MARK: - End-to-End: JSONL → Encrypt → Decrypt → Verify

    /// Simulate Mac reading JSONL, encrypting messages, iOS decrypting and displaying.
    func testSessionDataThroughEncryptedPipeline() async throws {
        let msgEncoder = MessageEncoder()
        let msgDecoder = MessageDecoder()

        let mac = CryptoManager()
        let ios = CryptoManager()
        let macKP = try await mac.generateKeyPair()
        let iosKP = try await ios.generateKeyPair()
        try await mac.deriveSharedSecret(theirPublicKey: iosKP.publicKey)
        try await ios.deriveSharedSecret(theirPublicKey: macKP.publicKey)

        // Mac reads JSONL session file
        let jsonl = """
        {"type":"human","content":"Build the project","session_id":"proj-1","timestamp":"2024-06-15T10:00:00Z"}
        {"type":"assistant","content":"Running swift build...","session_id":"proj-1","timestamp":"2024-06-15T10:00:01Z"}
        {"type":"tool_use","content":"Executing: swift build","session_id":"proj-1","timestamp":"2024-06-15T10:00:02Z"}
        {"type":"tool_result","content":"Build complete! (0.42s)","session_id":"proj-1","timestamp":"2024-06-15T10:00:05Z"}
        {"type":"assistant","content":"The build succeeded with no errors.","session_id":"proj-1","timestamp":"2024-06-15T10:00:06Z"}
        """

        let sessionMessages = parser.parse(jsonl)
        XCTAssertEqual(sessionMessages.count, 5)

        // Mac creates session update
        let session = Session(
            id: "proj-1",
            projectPath: "/Users/dev/myapp",
            status: .active,
            messageCount: sessionMessages.count
        )

        // Mac sends session update through encrypted channel
        let sessionMsg = try BalconyMessage.create(type: .sessionUpdate, payload: session)
        let encSession = try await mac.encrypt(try msgEncoder.encode(sessionMsg))
        let decSession = try msgDecoder.decode(try await ios.decrypt(encSession))
        let receivedSession = try decSession.decodePayload(Session.self)
        XCTAssertEqual(receivedSession.id, "proj-1")
        XCTAssertEqual(receivedSession.messageCount, 5)

        // Mac sends each message as terminal output
        var receivedContents: [String] = []
        for sm in sessionMessages {
            let termMsg = try BalconyMessage.create(type: .terminalOutput, payload: sm.content)
            let encrypted = try await mac.encrypt(try msgEncoder.encode(termMsg))
            let decrypted = try msgDecoder.decode(try await ios.decrypt(encrypted))
            let content = try decrypted.decodePayload(String.self)
            receivedContents.append(content)
        }

        XCTAssertEqual(receivedContents.count, 5)
        XCTAssertEqual(receivedContents[0], "Build the project")
        XCTAssertEqual(receivedContents[3], "Build complete! (0.42s)")
        XCTAssertEqual(receivedContents[4], "The build succeeded with no errors.")
    }

    // MARK: - Session Switching

    /// Simulate iOS switching between two active sessions.
    func testMultipleSessionSwitching() async throws {
        let msgEncoder = MessageEncoder()
        let msgDecoder = MessageDecoder()

        let mac = CryptoManager()
        let ios = CryptoManager()
        let macKP = try await mac.generateKeyPair()
        let iosKP = try await ios.generateKeyPair()
        try await mac.deriveSharedSecret(theirPublicKey: iosKP.publicKey)
        try await ios.deriveSharedSecret(theirPublicKey: macKP.publicKey)

        // Two active sessions
        let sessionA = Session(id: "sess-A", projectPath: "/project-alpha", status: .active, messageCount: 10)
        let sessionB = Session(id: "sess-B", projectPath: "/project-beta", status: .waitingForInput, messageCount: 3)

        // Mac sends session list
        let listMsg = try BalconyMessage.create(type: .sessionList, payload: [sessionA, sessionB])
        let encList = try await mac.encrypt(try msgEncoder.encode(listMsg))
        let decList = try msgDecoder.decode(try await ios.decrypt(encList))
        let sessions = try decList.decodePayload([Session].self)
        XCTAssertEqual(sessions.count, 2)

        // iOS subscribes to session A
        let subA = try BalconyMessage.create(type: .sessionSubscribe, payload: ["sessionId": "sess-A"])
        let encSubA = try await ios.encrypt(try msgEncoder.encode(subA))
        let decSubA = try msgDecoder.decode(try await mac.decrypt(encSubA))
        let subPayloadA = try decSubA.decodePayload([String: String].self)
        XCTAssertEqual(subPayloadA["sessionId"], "sess-A")

        // Mac sends terminal output for session A
        let outputA = try BalconyMessage.create(type: .terminalOutput, payload: "Alpha output")
        let encOutA = try await mac.encrypt(try msgEncoder.encode(outputA))
        let decOutA = try msgDecoder.decode(try await ios.decrypt(encOutA))
        XCTAssertEqual(try decOutA.decodePayload(String.self), "Alpha output")

        // iOS switches to session B (unsubscribe A, subscribe B)
        let unsubA = try BalconyMessage.create(type: .sessionUnsubscribe, payload: ["sessionId": "sess-A"])
        let encUnsubA = try await ios.encrypt(try msgEncoder.encode(unsubA))
        let decUnsubA = try msgDecoder.decode(try await mac.decrypt(encUnsubA))
        XCTAssertEqual(decUnsubA.type, .sessionUnsubscribe)

        let subB = try BalconyMessage.create(type: .sessionSubscribe, payload: ["sessionId": "sess-B"])
        let encSubB = try await ios.encrypt(try msgEncoder.encode(subB))
        let decSubB = try msgDecoder.decode(try await mac.decrypt(encSubB))
        let subPayloadB = try decSubB.decodePayload([String: String].self)
        XCTAssertEqual(subPayloadB["sessionId"], "sess-B")

        // Mac sends terminal output for session B
        let outputB = try BalconyMessage.create(type: .terminalOutput, payload: "Beta output")
        let encOutB = try await mac.encrypt(try msgEncoder.encode(outputB))
        let decOutB = try msgDecoder.decode(try await ios.decrypt(encOutB))
        XCTAssertEqual(try decOutB.decodePayload(String.self), "Beta output")
    }
}
