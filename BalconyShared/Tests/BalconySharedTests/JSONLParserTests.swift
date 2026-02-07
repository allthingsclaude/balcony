import XCTest
@testable import BalconyShared

final class JSONLParserTests: XCTestCase {

    func testParseValidLines() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {"type":"assistant","content":"Hi there!","session_id":"s1","timestamp":"2024-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .human)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testSkipMalformedLines() {
        let parser = JSONLParser()
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"s1","timestamp":"2024-01-01T00:00:00Z"}
        {invalid json here
        {"type":"assistant","content":"World","session_id":"s1","timestamp":"2024-01-01T00:00:01Z"}
        """

        let messages = parser.parse(jsonl)
        XCTAssertEqual(messages.count, 2)
    }

    func testEmptyInput() {
        let parser = JSONLParser()
        let messages = parser.parse("")
        XCTAssertEqual(messages.count, 0)
    }
}
