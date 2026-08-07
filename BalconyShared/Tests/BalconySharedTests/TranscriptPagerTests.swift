import XCTest
@testable import BalconyShared

/// Exercises the backward transcript reader that makes opening a long session
/// instant: the last page of turns must come out of a 25 MB file in the same
/// shape it would come out of a 2 KB one, and paging back with the returned
/// cursor must walk the whole file exactly once with no gaps or repeats.
final class TranscriptPagerTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    /// One user turn per line, `uuid` = `u<index>`, with `filler` bytes of body
    /// so multi-chunk scans can be forced.
    private func userLine(_ index: Int, filler: Int = 0) -> String {
        let text = "msg\(index)" + String(repeating: "x", count: filler)
        return #"{"type":"user","uuid":"u\#(index)","message":{"role":"user","content":"\#(text)"}}"#
    }

    private func write(_ lines: [String], trailingNewline: Bool = true, name: String = "t.jsonl") throws -> String {
        let path = directory.appendingPathComponent(name).path
        var body = lines.joined(separator: "\n")
        if trailingNewline { body += "\n" }
        try Data(body.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    private func ids(_ page: TranscriptPager.Page) -> [String] {
        page.events.map(\.id)
    }

    private func size(of path: String) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Page from the file's end to its start, returning every id in order.
    private func walkBackwards(_ path: String, pageSize: Int) throws -> [String] {
        let fileSize = try size(of: path)
        var cursor = TranscriptPager.lastLineBoundary(inFileAt: path, size: fileSize).lineEnd
        var all: [String] = []
        // Bounded so a cursor that fails to advance fails the test instead of hanging.
        for _ in 0..<1000 {
            let page = TranscriptPager.eventsBackwards(fromFileAt: path, end: cursor, limit: pageSize)
            all.insert(contentsOf: ids(page), at: 0)
            guard page.hasMore else { return all }
            XCTAssertLessThan(page.start, cursor, "cursor must move towards the start of the file")
            cursor = page.start
        }
        XCTFail("paging did not terminate")
        return all
    }

    // MARK: - Tail snapshot

    func testReturnsLastTurnsInChronologicalOrder() throws {
        let path = try write((1...10).map { userLine($0) })
        let end = TranscriptPager.lastLineBoundary(inFileAt: path, size: try size(of: path)).lineEnd

        let page = TranscriptPager.eventsBackwards(fromFileAt: path, end: end, limit: 3)
        XCTAssertEqual(ids(page), ["u8", "u9", "u10"])
        XCTAssertTrue(page.hasMore)
    }

    func testShorterThanLimitReachesStartOfFile() throws {
        let path = try write((1...4).map { userLine($0) })
        let end = TranscriptPager.lastLineBoundary(inFileAt: path, size: try size(of: path)).lineEnd

        let page = TranscriptPager.eventsBackwards(fromFileAt: path, end: end, limit: 20)
        XCTAssertEqual(ids(page), ["u1", "u2", "u3", "u4"])
        XCTAssertEqual(page.start, 0)
        XCTAssertFalse(page.hasMore)
    }

    /// A turn Claude Code is mid-write must not be parsed as history — it is the
    /// tailer's `leftover`, completed by the next append.
    func testTrailingPartialLineIsSplitOffNotParsed() throws {
        let complete = (1...3).map { userLine($0) }
        let partial = #"{"type":"user","uuid":"u4","message":{"role":"user","cont"#
        let path = try write(complete + [partial], trailingNewline: false)

        let (lineEnd, partialBytes) = TranscriptPager.lastLineBoundary(inFileAt: path, size: try size(of: path))
        XCTAssertEqual(String(decoding: partialBytes, as: UTF8.self), partial)

        let page = TranscriptPager.eventsBackwards(fromFileAt: path, end: lineEnd, limit: 10)
        XCTAssertEqual(ids(page), ["u1", "u2", "u3"])
    }

    func testFileWithNoNewlineAtAllYieldsNoBoundary() throws {
        let path = try write([userLine(1)], trailingNewline: false)
        let (lineEnd, partial) = TranscriptPager.lastLineBoundary(inFileAt: path, size: try size(of: path))
        XCTAssertEqual(lineEnd, 0)
        XCTAssertEqual(String(decoding: partial, as: UTF8.self), userLine(1))
        XCTAssertTrue(TranscriptPager.eventsBackwards(fromFileAt: path, end: lineEnd, limit: 10).events.isEmpty)
    }

    // MARK: - Paging back

    func testPagingBackwardsCoversEveryTurnExactlyOnce() throws {
        let path = try write((1...25).map { userLine($0) })
        XCTAssertEqual(try walkBackwards(path, pageSize: 4), (1...25).map { "u\($0)" })
    }

    /// The page size dividing the turn count evenly is the case where an
    /// off-by-one in the cursor shows up as a dropped or repeated turn.
    func testPagingBackwardsWithExactMultiplePageSize() throws {
        let path = try write((1...20).map { userLine($0) })
        XCTAssertEqual(try walkBackwards(path, pageSize: 5), (1...20).map { "u\($0)" })
    }

    /// Records that aren't turns (summaries, `file-history-snapshot`, the caveat
    /// banner) must be skipped without stalling the walk or being counted.
    func testSkipsNonEventRecordsWhilePaging() throws {
        var lines: [String] = []
        for i in 1...12 {
            lines.append(#"{"type":"summary","summary":"noise \#(i)"}"#)
            lines.append(userLine(i))
            lines.append("")   // blank lines appear in real transcripts
        }
        let path = try write(lines)
        XCTAssertEqual(try walkBackwards(path, pageSize: 3), (1...12).map { "u\($0)" })
    }

    // MARK: - Chunk boundaries

    /// Turns far larger than one backward read must be reassembled from the
    /// fragment carried between chunks, not truncated at the chunk seam.
    func testTurnsSpanningManyChunksAreReassembled() throws {
        // Each line is ~120 KB, so a 256 KB read covers roughly two of them and
        // every scan crosses seams mid-line.
        let path = try write((1...8).map { userLine($0, filler: 120_000) })
        let all = try walkBackwards(path, pageSize: 3)
        XCTAssertEqual(all, (1...8).map { "u\($0)" })

        // Content survives the seam intact, not just the id.
        let end = TranscriptPager.lastLineBoundary(inFileAt: path, size: try size(of: path)).lineEnd
        let page = TranscriptPager.eventsBackwards(fromFileAt: path, end: end, limit: 1)
        guard case .text(let text)? = page.events.first?.blocks.first else {
            return XCTFail("expected a text block")
        }
        XCTAssertEqual(text.count, "msg8".count + 120_000)
    }

    /// A single turn bigger than one whole chunk exercises the path where a
    /// backward read finds no newline at all.
    func testSingleTurnLargerThanOneChunk() throws {
        let path = try write([userLine(1, filler: 400_000), userLine(2)])
        XCTAssertEqual(try walkBackwards(path, pageSize: 1), ["u1", "u2"])
    }

    // MARK: - Degenerate inputs

    func testEmptyAndMissingFiles() throws {
        let empty = try write([], trailingNewline: false, name: "empty.jsonl")
        XCTAssertEqual(TranscriptPager.lastLineBoundary(inFileAt: empty, size: 0).lineEnd, 0)
        XCTAssertTrue(TranscriptPager.eventsBackwards(fromFileAt: empty, end: 0, limit: 10).events.isEmpty)

        let missing = directory.appendingPathComponent("nope.jsonl").path
        let page = TranscriptPager.eventsBackwards(fromFileAt: missing, end: 500, limit: 10)
        XCTAssertTrue(page.events.isEmpty)
        XCTAssertFalse(page.hasMore)
    }

    func testZeroLimitReturnsNothing() throws {
        let path = try write((1...5).map { userLine($0) })
        let end = TranscriptPager.lastLineBoundary(inFileAt: path, size: try size(of: path)).lineEnd
        XCTAssertTrue(TranscriptPager.eventsBackwards(fromFileAt: path, end: end, limit: 0).events.isEmpty)
    }
}
