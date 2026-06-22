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
/// Precision is the priority: suppressing a genuine "Claude is done" message
/// would silently swallow a notification the user wants, which is worse than
/// letting an offload message through (the debounce still absorbs quick
/// flickers). So matching is deliberately conservative — it keys off Claude's
/// own first-person dispatch verbs and explicit "waiting on the work" phrasing,
/// not loose mentions of "workflow"/"agents". Some unusual offload phrasings are
/// therefore missed by design; those fall back to the debounce.
public enum BackgroundWorkDetector {

    /// Whether `message` indicates Claude is waiting on its own background work
    /// (a workflow or background agents it just launched) and will resume itself.
    public static func indicatesPendingBackgroundWork(_ message: String) -> Bool {
        let text = message.lowercased()

        // Phrases that, alone, mean Claude is awaiting its own async work. Tied to
        // the work ("it/them/the workflow … to complete"), never to the user, so
        // "I'll wait for your reply" (a genuine idle) is not matched.
        for phrase in waitingPhrases where text.contains(phrase) {
            return true
        }

        // Everything else requires a helper noun (Claude's own async helpers)…
        let hasHelper = helperNouns.contains { text.contains($0) }
        guard hasHelper else { return false }

        // …plus either a first-person dispatch verb (Claude is handing work off)…
        if launchVerbs.contains(where: { text.contains($0) }) { return true }

        // …or an explicit "still in flight" cue about that helper.
        return inFlightCues.contains { text.contains($0) }
    }

    /// Phrases Claude uses when waiting on its own async work or pointing at it.
    /// Each is anchored to the work, not to the user.
    private static let waitingPhrases = [
        "/workflows",
        "report back once",
        "report back when",
        "waiting for it to complete",
        "waiting for it to finish",
        "waiting for them to complete",
        "waiting for them to finish",
        "wait for it to complete",
        "wait for it to finish",
        "wait for them to complete",
        "wait for them to finish",
        "waiting for the workflow",
        "waiting for the agents",
        "waiting for the results",
    ]

    /// Nouns naming Claude's own asynchronous helpers. "agent" also covers
    /// "agents"/"subagent"/"background agent".
    private static let helperNouns = [
        "agent",
        "sub-agent",
        "workflow",
        "in parallel",
        "parallel reader",
    ]

    /// First-person dispatch verbs; paired with a helper noun they mean Claude is
    /// handing work off, not finishing. Deliberately excludes "launch"/"start",
    /// which routinely appear in plain completions ("I launched the agents
    /// dashboard", "I started the workflow file").
    private static let launchVerbs = [
        "delegat",        // delegate / delegating / delegated
        "dispatch",       // dispatch / dispatching / dispatched
        "spin up",
        "spinning up",
        "spun up",
        "spawn",          // spawn / spawning / spawned
        "kick off",
        "kicking off",
        "kicked off",
        "offload",        // offload / offloading / offloaded
        "parallelize",
        "parallelizing",
        "fan out",
        "fanning out",
        "fanned out",
        "hand off",
        "handing off",
        "handed off",
    ]

    /// Cues that a named helper is still in flight. Kept narrow — bare "is
    /// running"/"in progress" appear in completions ("CI is running now").
    private static let inFlightCues = [
        "still running",
        "still in progress",
        "running in the background",
    ]
}
