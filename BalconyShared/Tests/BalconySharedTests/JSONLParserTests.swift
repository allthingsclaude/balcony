import XCTest
@testable import BalconyShared

final class JSONLParserTests: XCTestCase {

    func testParseRealClaudeCodeFormat() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"user","sessionId":"s1","cwd":"/Users/dev/project","message":{"role":"user","content":"Hello"},"timestamp":"2026-02-07T19:24:14.547Z"}
        {"type":"assistant","sessionId":"s1","cwd":"/Users/dev/project","message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}]},"timestamp":"2026-02-07T19:24:15.123Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Hello")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "Hi there!")
    }

    func testSkipProgressAndFileHistorySnapshot() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"file-history-snapshot","messageId":"abc","snapshot":{}}
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        {"type":"progress","data":{"type":"hook_progress"},"sessionId":"s1","timestamp":"2026-01-01T00:00:01Z"}
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"World"}]},"timestamp":"2026-01-01T00:00:02Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testSkipMetaMessages() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"user","sessionId":"s1","isMeta":true,"message":{"role":"user","content":"<command-name>/fast</command-name>"},"timestamp":"2026-01-01T00:00:00Z"}
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Real user message"},"timestamp":"2026-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Real user message")
    }

    func testSkipMalformedLines() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        {invalid json here
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"World"}]},"timestamp":"2026-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
    }

    func testEmptyInput() {
        let parser = JSONLParser()
        let messages = parser.parse("")
        XCTAssertEqual(messages.count, 0)
    }

    func testToolUseContentBlocks() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_123","name":"Read","input":{"file_path":"/src/main.swift"}}]},"timestamp":"2026-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].content.contains("[Tool: Read]"))
        XCTAssertTrue(messages[0].content.contains("/src/main.swift"))
    }

    func testMixedTextAndToolUseBlocks() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"assistant","sessionId":"s1","message":{"role":"assistant","content":[{"type":"text","text":"Let me read that file."},{"type":"tool_use","id":"toolu_456","name":"Bash","input":{"command":"swift build"}}]},"timestamp":"2026-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].content.contains("Let me read that file."))
        XCTAssertTrue(messages[0].content.contains("[Tool: Bash] swift build"))
    }

    func testFractionalTimestampParsing() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"user","sessionId":"s1","message":{"role":"user","content":"Hello"},"timestamp":"2026-02-07T19:24:14.547Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        // Verify the fractional timestamp was parsed (not fallback to Date())
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: messages[0].timestamp)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 7)
    }

    func testSessionIdCamelCase() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"user","sessionId":"abc-123-def","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].sessionId, "abc-123-def")
    }

    func testSessionIdSnakeCaseFallback() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"user","session_id":"legacy-id","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].sessionId, "legacy-id")
    }

    func testParseEntryExtractsCWD() {
        let parser = JSONLParser()
        let line = """
        {"type":"user","sessionId":"s1","cwd":"/Users/dev/myproject","message":{"role":"user","content":"Hello"},"timestamp":"2026-01-01T00:00:00Z"}
        """

        let entry = parser.parseEntry(line)
        XCTAssertNotNil(entry.message)
        XCTAssertEqual(entry.cwd, "/Users/dev/myproject")
        XCTAssertEqual(entry.sessionId, "s1")
    }

    func testLegacyTopLevelContentFormat() {
        // Backward compatibility: content at top level (not nested in "message")
        let parser = JSONLParser()
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {"type":"assistant","content":"Hi there!","session_id":"s1","timestamp":"2024-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .human)
        XCTAssertEqual(messages[0].content, "Hello")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "Hi there!")
    }
}
