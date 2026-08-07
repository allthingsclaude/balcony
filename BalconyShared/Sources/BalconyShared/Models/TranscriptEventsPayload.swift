import Foundation

/// A batch of structured transcript events for a session, sent Mac → iOS.
///
/// The Mac tails the session's JSONL transcript: it sends history once with
/// `reset == true` (initial snapshot, or after the file is rewritten by
/// compaction / `/clear`), then streams subsequent turns as append batches with
/// `reset == false`. iOS replaces its list on a reset and appends otherwise,
/// de-duplicating by `TranscriptEvent.id`.
///
/// The reset snapshot carries only the **last** `historyLimit` turns (see
/// `SessionSubscribePayload.historyLimit`) so a long session opens instantly.
/// `historyStart` is the cursor for walking further back — see
/// `TranscriptHistoryRequestPayload`.
public struct TranscriptEventsPayload: Codable, Sendable {
    public let sessionId: String
    public let events: [TranscriptEvent]
    /// When true, replace the existing transcript rather than appending.
    public let reset: Bool
    /// Byte offset in the transcript file where the oldest included event's line
    /// begins — pass it back as `beforeOffset` to page further into the past.
    /// Only meaningful on a reset batch; nil when the client didn't ask for a
    /// limited snapshot (legacy full-history mode).
    public let historyStart: UInt64?
    /// True when turns older than `historyStart` exist and can be paged in.
    public let hasMore: Bool?

    public init(
        sessionId: String,
        events: [TranscriptEvent],
        reset: Bool,
        historyStart: UInt64? = nil,
        hasMore: Bool? = nil
    ) {
        self.sessionId = sessionId
        self.events = events
        self.reset = reset
        self.historyStart = historyStart
        self.hasMore = hasMore
    }
}
