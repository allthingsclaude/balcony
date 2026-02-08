import XCTest
@testable import BalconyShared

final class SessionParserIntegrationTests: XCTestCase {

    let parser = JSONLParser()

    // MARK: - Realistic Session Parsing

    /// Parse a realistic Claude Code session with multiple message types.
    func testRealisticSessionParsing() {
        let jsonl = """
        {"type":"user","sessionId":"sess-001","cwd":"/Users/dev/myapp","message":{"role":"user","content":"Fix the bug in UserService.swift"},"timestamp":"2026-06-15T10:00:00.000Z"}
        {"type":"assistant","sessionId":"sess-001","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"text","text":"I'll look at UserService.swift and fix the bug."}]},"timestamp":"2026-06-15T10:00:02.100Z"}
        {"type":"assistant","sessionId":"sess-001","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"UserService.swift"}}]},"timestamp":"2026-06-15T10:00:03.200Z"}
        {"type":"assistant","sessionId":"sess-001","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"text","text":"I found the issue. The fetchUser method has a race condition."}]},"timestamp":"2026-06-15T10:00:05.500Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Fix the bug in UserService.swift")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "I'll look at UserService.swift and fix the bug.")
        XCTAssertEqual(messages[2].role, .assistant)
        XCTAssertTrue(messages[2].content.contains("[Tool: Read]"))
        XCTAssertEqual(messages[3].role, .assistant)

        for msg in messages {
            XCTAssertEqual(msg.sessionId, "sess-001")
        }
    }

    // MARK: - Incremental Parsing

    /// Simulate file tailing: parse first batch, then parse appended lines.
    func testIncrementalParsing() {
        let batch1 = """
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00.000Z"}
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}]},"timestamp":"2026-01-01T00:00:01.000Z"}
        """
        let messages1 = parser.parse(batch1)
        XCTAssertEqual(messages1.count, 2)

        // New lines appended to file
        let batch2 = """
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Fix the tests"},"timestamp":"2026-01-01T00:01:00.000Z"}
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"On it!"}]},"timestamp":"2026-01-01T00:01:01.000Z"}
        """
        let messages2 = parser.parse(batch2)
        XCTAssertEqual(messages2.count, 2)
        XCTAssertEqual(messages2[0].content, "Fix the tests")
    }

    // MARK: - Skipped Types

    /// Progress and file-history-snapshot lines should be skipped.
    func testSkippedTypes() {
        let jsonl = """
        {"type":"file-history-snapshot","messageId":"abc","snapshot":{"trackedFileBackups":{}}}
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        {"type":"progress","data":{"type":"hook_progress","hookEvent":"SessionStart"},"sessionId":"s1","timestamp":"2026-01-01T00:00:01Z"}
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}]},"timestamp":"2026-01-01T00:00:02Z"}
        {"type":"progress","data":{"type":"agent_progress"},"sessionId":"s1","timestamp":"2026-01-01T00:00:03Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    // MARK: - Incomplete Data

    /// Incomplete trailing line (file still being written) should be skipped.
    func testIncompleteTrailingLine() {
        let jsonl = """
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"Work
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .user)
    }

    // MARK: - Multiple Sessions

    /// Parse lines from different sessions independently.
    func testMultipleSessions() {
        let session1 = (0..<5).map { i in
            "{\"type\":\"user\",\"sessionId\":\"sess-A\",\"message\":{\"role\":\"user\",\"content\":\"Message \(i)\"},\"timestamp\":\"2026-01-01T00:00:0\(i).000Z\"}"
        }.joined(separator: "\n")

        let session2 = (0..<3).map { i in
            "{\"type\":\"assistant\",\"sessionId\":\"sess-B\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Reply \(i)\"}]},\"timestamp\":\"2026-01-01T00:00:0\(i).000Z\"}"
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
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"First paragraph."},{"type":"text","text":"Second paragraph."}]},"timestamp":"2026-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].content.contains("First paragraph."))
        XCTAssertTrue(messages[0].content.contains("Second paragraph."))
    }

    // MARK: - CWD Extraction

    /// parseEntries extracts CWD from lines.
    func testCWDExtraction() {
        let jsonl = """
        {"type":"user","sessionId":"s1","cwd":"/Users/dev/myapp","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        {"type":"assistant","sessionId":"s1","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]},"timestamp":"2026-01-01T00:00:01Z"}
        """

        let entries = parser.parseEntries(jsonl)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].cwd, "/Users/dev/myapp")
        XCTAssertEqual(entries[1].cwd, "/Users/dev/myapp")
        XCTAssertNotNil(entries[0].message)
        XCTAssertNotNil(entries[1].message)
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

        // Mac reads JSONL session file (real format)
        let jsonl = """
        {"type":"user","sessionId":"proj-1","cwd":"/Users/dev/myapp","message":{"role":"user","content":"Build the project"},"timestamp":"2026-06-15T10:00:00.000Z"}
        {"type":"assistant","sessionId":"proj-1","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"text","text":"Running swift build..."}]},"timestamp":"2026-06-15T10:00:01.100Z"}
        {"type":"assistant","sessionId":"proj-1","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"swift build"}}]},"timestamp":"2026-06-15T10:00:02.200Z"}
        {"type":"assistant","sessionId":"proj-1","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"text","text":"Build complete! (0.42s)"}]},"timestamp":"2026-06-15T10:00:05.300Z"}
        {"type":"assistant","sessionId":"proj-1","cwd":"/Users/dev/myapp","message":{"role":"assistant","content":[{"type":"text","text":"The build succeeded with no errors."}]},"timestamp":"2026-06-15T10:00:06.400Z"}
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
