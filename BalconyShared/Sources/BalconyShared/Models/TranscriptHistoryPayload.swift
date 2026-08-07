import Foundation

/// iOS → Mac: ask for the page of turns immediately *before* a byte offset.
///
/// Subscribing delivers only the tail of a session's transcript so the view
/// opens instantly (`TranscriptEventsPayload.historyStart`). Scrolling up walks
/// backwards from that cursor, one page at a time.
///
/// The cursor is a byte offset into the session's JSONL file, always at the
/// start of a line. A session's transcript is append-only, so offsets stay
/// valid; a rewrite (compaction, `/clear`) makes the Mac re-snapshot with
/// `reset == true`, which hands the client a fresh cursor.
public struct TranscriptHistoryRequestPayload: Codable, Sendable {
    public let sessionId: String
    /// Read backwards from here — the `historyStart` of the last batch received.
    public let beforeOffset: UInt64
    /// Maximum number of turns to return.
    public let limit: Int

    public init(sessionId: String, beforeOffset: UInt64, limit: Int) {
        self.sessionId = sessionId
        self.beforeOffset = beforeOffset
        self.limit = limit
    }
}

/// Mac → iOS: a page of older turns, to be prepended to the transcript.
public struct TranscriptHistoryPayload: Codable, Sendable {
    public let sessionId: String
    /// Turns in chronological order (oldest first), all older than the request's
    /// `beforeOffset`.
    public let events: [TranscriptEvent]
    /// Echo of the request's cursor, so a client that has since reset (new
    /// snapshot, session switch) can discard a stale page.
    public let beforeOffset: UInt64
    /// New cursor: where the oldest returned event's line begins. Zero once the
    /// start of the file has been reached.
    public let historyStart: UInt64
    /// True when turns older than `historyStart` remain.
    public let hasMore: Bool

    public init(
        sessionId: String,
        events: [TranscriptEvent],
        beforeOffset: UInt64,
        historyStart: UInt64,
        hasMore: Bool
    ) {
        self.sessionId = sessionId
        self.events = events
        self.beforeOffset = beforeOffset
        self.historyStart = historyStart
        self.hasMore = hasMore
    }
}
