import XCTest
@testable import BalconyShared

final class BackgroundWorkDetectorTests: XCTestCase {

    private func assertSuppressed(_ message: String, _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertTrue(
            BackgroundWorkDetector.indicatesPendingBackgroundWork(message),
            "Expected to suppress (offload/waiting): \(message)", file: file, line: line
        )
    }

    private func assertNotSuppressed(_ message: String, _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertFalse(
            BackgroundWorkDetector.indicatesPendingBackgroundWork(message),
            "Expected NOT to suppress (genuine completion / user-turn): \(message)", file: file, line: line
        )
    }

    // MARK: - Offload messages that must be suppressed

    /// The exact "Claude is done" panel bodies captured while offloading to a workflow.
    func testSuppressesObservedOffloadMessages() {
        assertSuppressed("I'll research how spaces, tabs, and projects are named and mutated across the codebase, then come back with a concrete approach. Since this spans several subsystems, I'll fan out parallel readers.")
        assertSuppressed("The research workflow is running in the background across the three entities plus the UX-pattern survey. I'll wait for it to complete.")
        assertSuppressed("I've kicked off a background research workflow that's reading the actual code for how scratch spaces, tabs, and projects are named/stored/rendered, plus surveying existing rename-UI patterns. I'll report back with a concrete approach once it completes.")
        assertSuppressed("Research workflow still running. Waiting for it to complete before reporting the rename approach.")
    }

    /// Common first-person dispatch phrasings.
    func testSuppressesDispatchPhrasings() {
        assertSuppressed("Let me delegate this to a few subagents.")
        assertSuppressed("I'm dispatching parallel agents to audit each module.")
        assertSuppressed("Spinning up background agents now.")
        assertSuppressed("Offloading the audit to subagents.")
        assertSuppressed("Let me parallelize this across several agents.")
        assertSuppressed("I'll hand off the migration to subagents.")
        assertSuppressed("Kicked off a workflow to migrate the call sites.")
        assertSuppressed("The subagents are still running — use /workflows to monitor progress.")
    }

    // MARK: - Genuine completions that must NOT be suppressed

    /// Reviewer's reproduced false positives — real completions that merely mention
    /// "workflow"/"agents"/"monitor". These must reach the user.
    func testDoesNotSuppressCompletionsMentioningWorkflowsOrAgents() {
        assertNotSuppressed("I've added a workflow to monitor the build status on every push. All set.")
        assertNotSuppressed("The new GitHub Actions workflow is now in progress on this PR.")
        assertNotSuppressed("I implemented the agents dashboard and the monitor view. Tests pass.")
        assertNotSuppressed("Done. The orchestration workflow file is committed; CI is running now.")
        assertNotSuppressed("I refactored the agents module. Let me know if you want me to wait for the next release.")
        assertNotSuppressed("I created the cron workflow; it'll report back results to Slack daily.")
        assertNotSuppressed("I updated the GitHub Actions workflow file.")
        assertNotSuppressed("I refactored the workflow engine and every test passes.")
    }

    /// Plain completions and genuine "your turn" messages.
    func testDoesNotSuppressGenuineIdle() {
        assertNotSuppressed("Done. The rename feature is implemented and all tests pass.")
        assertNotSuppressed("I've finished the refactor. Want me to add a migration guide?")
        assertNotSuppressed("The dev server is now running in the background on localhost:3000 — open it to see the change.")
        assertNotSuppressed("Fixed the crash. Let me know if you want anything else.")
        // "wait for" tied to the USER, not to background work — a genuine idle.
        assertNotSuppressed("I'll wait for your reply before making any further changes.")
        assertNotSuppressed("Let me know how you'd like to proceed and I'll wait for your go-ahead.")
        assertNotSuppressed("")
    }

    // MARK: - Robustness

    func testIsCaseInsensitive() {
        assertSuppressed("RESEARCH WORKFLOW STILL RUNNING. WAITING FOR IT TO COMPLETE.")
    }
}
