import Foundation

/// A batch of structured transcript events for a session, sent Mac → iOS.
///
/// The Mac tails the session's JSONL transcript: it sends the full history once
/// with `reset == true` (initial snapshot, or after the file is rewritten by
/// compaction / `/clear`), then streams subsequent turns as append batches with
/// `reset == false`. iOS replaces its list on a reset and appends otherwise,
/// de-duplicating by `TranscriptEvent.id`.
public struct TranscriptEventsPayload: Codable, Sendable {
    public let sessionId: String
    public let events: [TranscriptEvent]
    /// When true, replace the existing transcript rather than appending.
    public let reset: Bool

    public init(sessionId: String, events: [TranscriptEvent], reset: Bool) {
        self.sessionId = sessionId
        self.events = events
        self.reset = reset
    }
}
