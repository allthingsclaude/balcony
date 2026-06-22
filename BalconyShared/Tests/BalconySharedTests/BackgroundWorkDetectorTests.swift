import XCTest
@testable import BalconyShared

final class BackgroundWorkDetectorTests: XCTestCase {

    // MARK: - Offload messages that must be suppressed

    /// Real "Claude is done" panel bodies captured while offloading to a workflow.
    func testSuppressesObservedOffloadMessages() {
        let offloads = [
            "I'll research how spaces, tabs, and projects are named and mutated across the codebase, then come back with a concrete approach. Since this spans several subsystems, I'll fan out parallel readers.",
            "The research workflow is running in the background across the three entities plus the UX-pattern survey. I'll wait for it to complete.",
            "I've kicked off a background research workflow that's reading the actual code for how scratch spaces, tabs, and projects are named/stored/rendered, plus surveying existing rename-UI patterns. I'll report back with a concrete approach once it completes.",
            "Research workflow still running. Waiting for it to complete before reporting the rename approach.",
        ]
        for message in offloads {
            XCTAssertTrue(
                BackgroundWorkDetector.indicatesPendingBackgroundWork(message),
                "Expected offload message to be suppressed: \(message)"
            )
        }
    }

    func testSuppressesAgentAndWorkflowVariants() {
        let messages = [
            "Spawning parallel agents to audit each module; they're still running.",
            "Kicked off a workflow to migrate the call sites.",
            "The subagents are running — use /workflows to monitor progress.",
            "I'll wait for the agents to finish, then synthesize the results.",
        ]
        for message in messages {
            XCTAssertTrue(
                BackgroundWorkDetector.indicatesPendingBackgroundWork(message),
                "Expected to suppress: \(message)"
            )
        }
    }

    // MARK: - Genuine completions that must NOT be suppressed

    func testDoesNotSuppressGenuineCompletions() {
        let completions = [
            "Done. The rename feature is implemented and all tests pass.",
            "I've finished the refactor. Want me to add a migration guide?",
            "The dev server is now running in the background on localhost:3000 — open it to see the change.",
            "I refactored the workflow engine and every test passes.",
            "Fixed the crash. Let me know if you want anything else.",
            "",
        ]
        for message in completions {
            XCTAssertFalse(
                BackgroundWorkDetector.indicatesPendingBackgroundWork(message),
                "Expected NOT to suppress genuine completion: \(message)"
            )
        }
    }

    // MARK: - Robustness

    func testIsCaseInsensitive() {
        XCTAssertTrue(BackgroundWorkDetector.indicatesPendingBackgroundWork(
            "RESEARCH WORKFLOW STILL RUNNING. WAITING FOR IT TO COMPLETE."
        ))
    }

    /// A bare work noun with no in-progress cue is treated as a finished mention.
    func testWorkNounWithoutCueIsNotSuppressed() {
        XCTAssertFalse(BackgroundWorkDetector.indicatesPendingBackgroundWork(
            "I updated the GitHub Actions workflow file."
        ))
    }
}
