import XCTest
import BalconyShared

final class SessionMonitorTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("balcony-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Session Discovery

    func testDiscoverExistingSessions() async throws {
        // Create a fake session file before monitoring starts
        let projectDir = tempDir.appendingPathComponent("projects/abc123/sessions")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let sessionFile = projectDir.appendingPathComponent("session-001.jsonl")
        let jsonl = """
        {"type":"human","content":"Hello","session_id":"session-001","timestamp":"2025-01-01T00:00:00Z"}
        {"type":"assistant","content":"Hi there","session_id":"session-001","timestamp":"2025-01-01T00:00:01Z"}
        """
        try jsonl.write(to: sessionFile, atomically: true, encoding: .utf8)

        let monitor = SessionMonitor(claudeDir: tempDir.path)
        let events = await monitor.startMonitoring()

        // Collect events with a short timeout
        var discoveredSessions: [Session] = []
        var updatedSessions: [(Session, [SessionMessage])] = []

        let task = Task {
            for await event in events {
                switch event {
                case .sessionDiscovered(let session):
                    discoveredSessions.append(session)
                case .sessionUpdated(let session, let messages):
                    updatedSessions.append((session, messages))
                case .sessionEnded:
                    break
                }
            }
        }

        // Give the scan time to complete
        try await Task.sleep(nanoseconds: 500_000_000)
        await monitor.stopMonitoring()
        task.cancel()

        XCTAssertEqual(discoveredSessions.count, 1)
        XCTAssertEqual(discoveredSessions.first?.id, "session-001")
        XCTAssertEqual(discoveredSessions.first?.projectPath, "abc123")

        // Should have received an update with the parsed messages
        XCTAssertFalse(updatedSessions.isEmpty)
        if let (session, messages) = updatedSessions.first {
            XCTAssertEqual(session.id, "session-001")
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0].role, .human)
            XCTAssertEqual(messages[1].role, .assistant)
        }
    }

    func testGetSessionsReturnsSortedByActivity() async throws {
        let projectDir = tempDir.appendingPathComponent("projects/proj1/sessions")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Create two sessions
        let session1 = projectDir.appendingPathComponent("old-session.jsonl")
        try """
        {"type":"human","content":"Old","session_id":"old-session","timestamp":"2025-01-01T00:00:00Z"}
        """.write(to: session1, atomically: true, encoding: .utf8)

        let session2 = projectDir.appendingPathComponent("new-session.jsonl")
        try """
        {"type":"human","content":"New","session_id":"new-session","timestamp":"2025-06-01T00:00:00Z"}
        """.write(to: session2, atomically: true, encoding: .utf8)

        let monitor = SessionMonitor(claudeDir: tempDir.path)
        _ = await monitor.startMonitoring()

        try await Task.sleep(nanoseconds: 500_000_000)

        let sessions = await monitor.getSessions()
        XCTAssertEqual(sessions.count, 2)
        // Newer session should be first
        XCTAssertEqual(sessions.first?.id, "new-session")

        await monitor.stopMonitoring()
    }

    func testEndSessionUpdatesStatus() async throws {
        let projectDir = tempDir.appendingPathComponent("projects/proj1/sessions")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let sessionFile = projectDir.appendingPathComponent("test-session.jsonl")
        try """
        {"type":"human","content":"Hello","session_id":"test-session","timestamp":"2025-01-01T00:00:00Z"}
        """.write(to: sessionFile, atomically: true, encoding: .utf8)

        let monitor = SessionMonitor(claudeDir: tempDir.path)
        let events = await monitor.startMonitoring()

        var endedIds: [String] = []
        let task = Task {
            for await event in events {
                if case .sessionEnded(let id) = event {
                    endedIds.append(id)
                }
            }
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        await monitor.endSession(id: "test-session")
        try await Task.sleep(nanoseconds: 100_000_000)

        let session = await monitor.getSession(id: "test-session")
        XCTAssertEqual(session?.status, .completed)
        XCTAssertEqual(endedIds, ["test-session"])

        await monitor.stopMonitoring()
        task.cancel()
    }

    func testMonitorDetectsNewFiles() async throws {
        let projectDir = tempDir.appendingPathComponent("projects/proj1/sessions")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let monitor = SessionMonitor(claudeDir: tempDir.path)
        let events = await monitor.startMonitoring()

        var discoveredIds: [String] = []
        let task = Task {
            for await event in events {
                if case .sessionDiscovered(let session) = event {
                    discoveredIds.append(session.id)
                }
            }
        }

        // Wait for FSEvents to initialize
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Write a new session file AFTER monitoring started
        let newSession = projectDir.appendingPathComponent("dynamic-session.jsonl")
        try """
        {"type":"human","content":"Dynamic","session_id":"dynamic-session","timestamp":"2025-01-01T00:00:00Z"}
        """.write(to: newSession, atomically: true, encoding: .utf8)

        // Wait for FSEvents to fire (latency is 300ms + processing)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        await monitor.stopMonitoring()
        task.cancel()

        XCTAssertTrue(discoveredIds.contains("dynamic-session"),
                      "Expected to discover 'dynamic-session', got: \(discoveredIds)")
    }

    func testEmptyDirectoryNoErrors() async throws {
        // Projects dir doesn't exist yet - monitor should create it
        let monitor = SessionMonitor(claudeDir: tempDir.path)
        let events = await monitor.startMonitoring()

        try await Task.sleep(nanoseconds: 300_000_000)

        let sessions = await monitor.getSessions()
        XCTAssertTrue(sessions.isEmpty)

        await monitor.stopMonitoring()

        // Verify the projects dir was created
        let projectsDir = tempDir.appendingPathComponent("projects")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectsDir.path))
    }
}
