import XCTest
@testable import BalconyShared

final class TranscriptParserTests: XCTestCase {

    // MARK: - Single-record parsing

    func testPlainStringUserMessage() throws {
        let line = #"{"type":"user","uuid":"u1","timestamp":"2026-06-14T18:42:11.000Z","message":{"role":"user","content":"no thanks"}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertEqual(event.id, "u1")
        XCTAssertEqual(event.role, .user)
        XCTAssertEqual(event.blocks, [.text("no thanks")])
        XCTAssertFalse(event.isSidechain)
        XCTAssertNotNil(event.timestamp)
    }

    func testAssistantThinkingTextToolUse() throws {
        let line = #"""
        {"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Let me check.","signature":"x"},{"type":"text","text":"Cool, no worries. I'm here when you need me."},{"type":"tool_use","id":"toolu_1","name":"Read","input":{"file_path":"/src/login.ts"}}]}}
        """#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertEqual(event.role, .assistant)
        XCTAssertEqual(event.blocks, [
            .thinking("Let me check."),
            .text("Cool, no worries. I'm here when you need me."),
            .toolUse(id: "toolu_1", name: "Read", input: "/src/login.ts"),
        ])
    }

    func testToolResultArrayWithError() throws {
        let line = #"""
        {"type":"user","uuid":"u2","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","is_error":true,"content":[{"type":"text","text":"file not found"}]}]}}
        """#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertEqual(event.blocks, [.toolResult(toolUseID: "toolu_1", text: "file not found", isError: true)])
    }

    /// Base64 image data in a tool_result must never ride the wire — it collapses
    /// to a placeholder.
    func testToolResultImageStrippedToPlaceholder() throws {
        let huge = String(repeating: "A", count: 5000)
        let line = #"{"type":"user","uuid":"u3","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":[{"type":"image","source":{"type":"base64","data":"\#(huge)"}}]}]}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        guard case .toolResult(_, let text, _) = try XCTUnwrap(event.blocks.first) else {
            return XCTFail("expected tool_result")
        }
        XCTAssertEqual(text, "[image]")
        XCTAssertFalse(text.contains("AAA"))
    }

    func testStringToolResultIsTruncated() throws {
        let huge = String(repeating: "x", count: 5000)
        let line = #"{"type":"user","uuid":"u4","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"\#(huge)"}]}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        guard case .toolResult(_, let text, let isError) = try XCTUnwrap(event.blocks.first) else {
            return XCTFail("expected tool_result")
        }
        XCTAssertFalse(isError)
        XCTAssertEqual(text.count, TranscriptParser.maxToolResultChars + 1) // +1 for the ellipsis
        XCTAssertTrue(text.hasSuffix("…"))
    }

    func testUserImagePasteBlock() throws {
        let line = #"{"type":"user","uuid":"u5","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AAAA"}},{"type":"text","text":"look at this"}]}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertEqual(event.blocks, [.image(altText: "image"), .text("look at this")])
    }

    func testSidechainFlag() throws {
        let line = #"{"type":"assistant","uuid":"a2","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"sub-agent work"}]}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertTrue(event.isSidechain)
    }

    // MARK: - Tool input summaries

    func testBashCommandSummary() throws {
        let line = #"{"type":"assistant","uuid":"a3","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"swift test","description":"run tests"}}]}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertEqual(event.blocks, [.toolUse(id: "t", name: "Bash", input: "swift test")])
    }

    func testUnknownToolFallsBackToDescription() throws {
        let line = #"{"type":"assistant","uuid":"a4","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"MysteryTool","input":{"description":"do a thing"}}]}}"#
        let event = try XCTUnwrap(TranscriptParser.parseLine(Data(line.utf8)))
        XCTAssertEqual(event.blocks, [.toolUse(id: "t", name: "MysteryTool", input: "do a thing")])
    }

    // MARK: - Skipping non-message records

    func testMetadataRecordsAreSkipped() {
        for line in [
            #"{"type":"mode","sessionId":"s","mode":"normal"}"#,
            #"{"type":"ai-title","sessionId":"s","aiTitle":"Some Title"}"#,
            #"{"type":"permission-mode","sessionId":"s","permissionMode":"default"}"#,
            #"{"type":"file-history-snapshot","messageId":"m","snapshot":{}}"#,
            "",
            "not json",
        ] {
            XCTAssertNil(TranscriptParser.parseLine(Data(line.utf8)), "should skip: \(line)")
        }
    }

    func testEmptyContentProducesNoEvent() {
        let line = #"{"type":"assistant","uuid":"a5","message":{"role":"assistant","content":[{"type":"text","text":"   "}]}}"#
        XCTAssertNil(TranscriptParser.parseLine(Data(line.utf8)))
    }

    // MARK: - Multi-line blob

    func testParseBlobPreservesOrderAndFilters() {
        let blob = [
            #"{"type":"mode","sessionId":"s","mode":"normal"}"#,
            #"{"type":"user","uuid":"u1","message":{"role":"user","content":"yooo"}}"#,
            #"{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"yo! what's up?"}]}}"#,
            #"{"type":"ai-title","sessionId":"s","aiTitle":"t"}"#,
            #"{"type":"user","uuid":"u2","message":{"role":"user","content":"no thanks"}}"#,
        ].joined(separator: "\n")

        let events = TranscriptParser.parse(blob)
        XCTAssertEqual(events.map(\.id), ["u1", "a1", "u2"])
        XCTAssertEqual(events.map(\.role), [.user, .assistant, .user])
    }

    // MARK: - Wire round-trip

    func testTranscriptEventCodableRoundTrip() throws {
        let event = TranscriptEvent(
            id: "a1",
            role: .assistant,
            blocks: [
                .thinking("hmm"),
                .text("hi"),
                .toolUse(id: "t1", name: "Bash", input: "ls"),
                .toolResult(toolUseID: "t1", text: "out", isError: false),
                .image(altText: "image"),
            ],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isSidechain: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(event)
        let decoded = try decoder.decode(TranscriptEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testPayloadCodableRoundTrip() throws {
        let payload = TranscriptEventsPayload(
            sessionId: "s1",
            events: [TranscriptEvent(id: "u1", role: .user, blocks: [.text("hi")])],
            reset: true
        )
        let msg = try BalconyMessage.create(type: .transcriptEvents, payload: payload)
        XCTAssertEqual(msg.type, .transcriptEvents)
        let decoded = try msg.decodePayload(TranscriptEventsPayload.self)
        XCTAssertEqual(decoded.sessionId, "s1")
        XCTAssertTrue(decoded.reset)
        XCTAssertEqual(decoded.events, payload.events)
    }
}
