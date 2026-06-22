import Foundation

/// Heuristics for deciding whether Claude's final assistant message means it has
/// offloaded work to its own background workflow/subagents — and will resume on
/// its own — rather than genuinely finishing and waiting for the user.
///
/// Balcony learns "Claude finished" from the `Stop` hook, but `Stop` also fires
/// every time Claude yields control, including right after it launches a
/// background workflow or background agents. Those moments are not "your turn",
/// so surfacing an idle prompt for them makes the Mac "Claude is done" panel and
/// the iOS "finished — your turn" notification fire spuriously (flickering when
/// Claude resumes quickly, or lingering while the background work runs).
///
/// Claude Code exposes no structural "background work pending" signal to the
/// hooks Balcony registers (`Notification`/`PreToolUse`/`Stop`/`SessionStart` —
/// there is no `PostToolUse`/`SubagentStop`), and a background tool's result is
/// acknowledged immediately so the transcript tail looks idle while the work
/// runs. The assistant message text is therefore the only available cue.
///
/// Tuning bias: prefer false negatives over false positives. When unsure we let
/// the idle prompt through (the debounce still absorbs quick flickers) rather
/// than risk swallowing a genuine "Claude is done".
public enum BackgroundWorkDetector {

    /// Whether `message` indicates Claude is waiting on its own background work
    /// (a workflow or background agents it just launched) and will resume itself.
    public static func indicatesPendingBackgroundWork(_ message: String) -> Bool {
        let text = message.lowercased()

        // Unambiguous orchestration phrasing — Claude only says these when it is
        // fanning work out to its own agents/workflows.
        for phrase in standalonePhrases where text.contains(phrase) {
            return true
        }

        // Otherwise require BOTH a background-work noun and an in-progress/waiting
        // cue, so an incidental mention of "workflow" in a finished summary (e.g.
        // "I refactored the workflow engine and tests pass") does not trip, and a
        // benign "the dev server is running in the background" (no work noun) is
        // still treated as a genuine completion the user should hear about.
        let hasNoun = workNouns.contains { text.contains($0) }
        guard hasNoun else { return false }
        return progressCues.contains { text.contains($0) }
    }

    /// Phrases specific enough to Claude's own orchestration to act alone.
    private static let standalonePhrases = [
        "/workflows",
        "fan out parallel",
        "fanning out",
        "kicked off a background",
        "kicked off a workflow",
    ]

    /// Nouns that name Claude's own asynchronous helpers.
    private static let workNouns = [
        "workflow",
        "subagent",
        "sub-agent",
        "background agent",
        "background task",
        "parallel agent",
        "parallel reader",
        "agents",
    ]

    /// Cues that the named work is still in flight (Claude has not finished).
    private static let progressCues = [
        "still running",
        "is running",
        "are running",
        "kicked off",
        "in progress",
        "to complete",
        "to finish",
        "waiting for",
        "wait for",
        "in the background",
        "report back",
        "monitor",
    ]
}
