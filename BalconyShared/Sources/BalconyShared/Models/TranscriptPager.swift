import Foundation

/// Reads a Claude Code JSONL transcript *backwards*, a page of turns at a time.
///
/// Opening a session should cost the same whether its transcript is 8 KB or
/// 25 MB, so the newest turns are found by seeking to the end of the file and
/// walking back — never by parsing from the top. Scrolling into the past
/// continues from where the previous page stopped, using a byte offset as the
/// cursor: a session's transcript is append-only, so offsets stay valid for its
/// lifetime, and a rewrite (compaction, `/clear`) is detected as a size change
/// that re-snapshots the whole view.
public enum TranscriptPager {

    /// A page of turns read backwards out of a transcript.
    public struct Page: Sendable {
        /// Turns in chronological order (oldest first).
        public let events: [TranscriptEvent]
        /// Byte offset where the oldest returned turn's line begins — the `end`
        /// for the next, older page. Zero once the file's start is reached.
        public let start: UInt64

        public init(events: [TranscriptEvent], start: UInt64) {
            self.events = events
            self.start = start
        }

        /// True when turns older than `start` remain in the file.
        public var hasMore: Bool { start > 0 }
    }

    /// Bytes read per backward step. Comfortably larger than a typical turn, so
    /// a page of history is usually one or two reads.
    public static let chunkSize = 256 * 1024

    private static let newline = UInt8(ascii: "\n")

    // MARK: - Paging

    /// Walk backwards through `[0, end)` collecting the last `limit` parseable
    /// turns, oldest first in the result.
    ///
    /// `end` must sit on a line boundary — the offset just past a newline, which
    /// is what ``lastLineBoundary(inFileAt:size:)`` and a previous page's
    /// ``Page/start`` both return. The scan keeps a cursor on that boundary and
    /// reads fixed-size chunks below it; because the region always closes on a
    /// newline, every piece split out of a chunk is a whole line except the
    /// leading fragment, which is carried into the next (earlier) chunk.
    ///
    /// Returns at most `limit` events. A short page therefore always means the
    /// start of the file was reached, never that a batch of unparseable
    /// metadata records got in the way — so `hasMore` is trustworthy.
    public static func eventsBackwards(fromFileAt path: String, end: UInt64, limit: Int) -> Page {
        guard end > 0, limit > 0,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        else { return Page(events: [], start: 0) }
        defer { try? handle.close() }

        // Step over the newline closing the region, so the last piece of the
        // first chunk is a complete line rather than an empty tail.
        var cursor = end
        if let terminator = readBytes(handle, at: end - 1, count: 1), terminator.first == newline {
            cursor -= 1
        }

        var collected: [TranscriptEvent] = []   // newest first while scanning
        var oldestLineStart: UInt64 = 0
        var fragment: [UInt8] = []              // leading partial line, completed by the earlier chunk
        var reachedLimit = false

        while cursor > 0 && !reachedLimit {
            let count = Int(min(UInt64(chunkSize), cursor))
            let chunkStart = cursor - UInt64(count)
            guard var buffer = readBytes(handle, at: chunkStart, count: count) else { break }
            cursor = chunkStart
            buffer.append(contentsOf: fragment)
            fragment = []

            // Offset within `buffer` at which each piece begins.
            var starts: [Int] = [0]
            for i in buffer.indices where buffer[i] == newline {
                starts.append(i + 1)
            }
            // Piece 0 runs from the chunk's start to the first newline: a
            // fragment, unless this chunk reaches the beginning of the file.
            let firstWhole = chunkStart == 0 ? 0 : 1

            var index = starts.count - 1
            while index >= firstWhole {
                let lineStart = starts[index]
                let lineEnd = index + 1 < starts.count ? starts[index + 1] - 1 : buffer.count
                index -= 1
                guard lineEnd > lineStart,
                      let event = TranscriptParser.parseLine(Data(buffer[lineStart..<lineEnd]))
                else { continue }
                collected.append(event)
                if collected.count >= limit {
                    oldestLineStart = chunkStart + UInt64(lineStart)
                    reachedLimit = true
                    break
                }
            }

            if !reachedLimit && firstWhole == 1 {
                let fragmentEnd = starts.count > 1 ? starts[1] - 1 : buffer.count
                fragment = Array(buffer[0..<fragmentEnd])
            }
        }

        return Page(events: collected.reversed(), start: oldestLineStart)
    }

    /// Split a transcript's tail at its final newline. Everything after it is a
    /// turn still being written, which a tailer must carry over rather than
    /// parse; everything before it is whole lines.
    ///
    /// - Returns: the offset just past the final newline (a line boundary
    ///   suitable for ``eventsBackwards(fromFileAt:end:limit:)``) and the
    ///   partial bytes that follow it.
    public static func lastLineBoundary(inFileAt path: String, size: UInt64) -> (lineEnd: UInt64, partial: Data) {
        guard size > 0, let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return (0, Data())
        }
        defer { try? handle.close() }

        var cursor = size
        var tail = Data()
        while cursor > 0 {
            let count = Int(min(UInt64(chunkSize), cursor))
            let chunkStart = cursor - UInt64(count)
            guard let bytes = readBytes(handle, at: chunkStart, count: count) else { break }
            cursor = chunkStart
            if let index = bytes.lastIndex(of: newline) {
                var partial = Data(bytes[(index + 1)...])
                partial.append(tail)
                return (chunkStart + UInt64(index) + 1, partial)
            }
            var combined = Data(bytes)
            combined.append(tail)
            tail = combined
        }
        return (0, tail)
    }

    // MARK: - Helpers

    /// Read exactly `count` bytes at `offset`, or nil if the file can't supply
    /// them (it shrank mid-scan).
    private static func readBytes(_ handle: FileHandle, at offset: UInt64, count: Int) -> [UInt8]? {
        guard count > 0,
              (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count),
              data.count == count
        else { return nil }
        return [UInt8](data)
    }
}
