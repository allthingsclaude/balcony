import XCTest
import BalconyShared

final class HookManagerTests: XCTestCase {

    private var tempHooksDir: URL!
    private var tempSocketPath: String!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        tempHooksDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("balcony-hooks-\(id)")
        tempSocketPath = "/tmp/balcony-test-\(id).sock"
        try? FileManager.default.createDirectory(at: tempHooksDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempHooksDir)
        unlink(tempSocketPath)
        super.tearDown()
    }

    // MARK: - Hook Installation

    func testInstallHooksCreatesScripts() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        try await manager.installHooks()

        let fm = FileManager.default
        let expectedHooks = ["PreToolUse.sh", "PostToolUse.sh", "Notification.sh", "Stop.sh"]
        for hookFile in expectedHooks {
            let path = tempHooksDir.appendingPathComponent(hookFile).path
            XCTAssertTrue(fm.fileExists(atPath: path), "Missing hook: \(hookFile)")

            // Verify executable permission
            let attrs = try fm.attributesOfItem(atPath: path)
            let perms = attrs[.posixPermissions] as? Int
            XCTAssertEqual(perms, 0o755, "Hook \(hookFile) should be executable")
        }
    }

    func testInstallHooksDoesNotOverwriteExisting() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        // Pre-create a hook with custom content
        let customHook = tempHooksDir.appendingPathComponent("PreToolUse.sh")
        try "#!/bin/bash\n# Custom hook".write(to: customHook, atomically: true, encoding: .utf8)

        try await manager.installHooks()

        // Should not have been overwritten
        let content = try String(contentsOf: customHook, encoding: .utf8)
        XCTAssertTrue(content.contains("Custom hook"))
    }

    func testRemoveHooksDeletesScripts() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        try await manager.installHooks()
        try await manager.removeHooks()

        let fm = FileManager.default
        let expectedHooks = ["PreToolUse.sh", "PostToolUse.sh", "Notification.sh", "Stop.sh"]
        for hookFile in expectedHooks {
            let path = tempHooksDir.appendingPathComponent(hookFile).path
            XCTAssertFalse(fm.fileExists(atPath: path), "Hook should be removed: \(hookFile)")
        }
    }

    func testHookScriptContainsSocketPath() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        try await manager.installHooks()

        let hookPath = tempHooksDir.appendingPathComponent("PreToolUse.sh")
        let content = try String(contentsOf: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("/tmp/balcony.sock"), "Hook should reference the socket path")
        XCTAssertTrue(content.contains("nc -U"), "Hook should use netcat to send to socket")
    }

    // MARK: - Socket Listener

    func testStartAndStopListening() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        let events = await manager.startListening()

        // Socket file should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempSocketPath),
                      "Socket file should be created")

        await manager.stopListening()

        // Socket file should be cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempSocketPath),
                       "Socket file should be removed after stop")
    }

    func testSocketReceivesHookEvent() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        let events = await manager.startListening()

        // Give the socket server time to start
        try await Task.sleep(nanoseconds: 300_000_000)

        var receivedEvents: [HookEvent] = []
        let task = Task {
            for await event in events {
                receivedEvents.append(event)
            }
        }

        // Send a hook event via the Unix socket (simulating what the hook script does)
        let hookPayload = """
        {"hook": "PreToolUse", "data": {"session_id": "test-123", "tool": "Read", "input": "/tmp/file.txt"}}
        """
        sendToSocket(socketPath: tempSocketPath, data: hookPayload)

        // Wait for processing
        try await Task.sleep(nanoseconds: 500_000_000)

        await manager.stopListening()
        task.cancel()

        XCTAssertEqual(receivedEvents.count, 1)
        if case .preToolUse(let sessionId, let toolName, let input) = receivedEvents.first {
            XCTAssertEqual(sessionId, "test-123")
            XCTAssertEqual(toolName, "Read")
            XCTAssertEqual(input, "/tmp/file.txt")
        } else {
            XCTFail("Expected preToolUse event, got: \(String(describing: receivedEvents.first))")
        }
    }

    func testSocketReceivesMultipleEventTypes() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        let events = await manager.startListening()
        try await Task.sleep(nanoseconds: 300_000_000)

        var receivedEvents: [HookEvent] = []
        let task = Task {
            for await event in events {
                receivedEvents.append(event)
            }
        }

        // Send different event types
        sendToSocket(socketPath: tempSocketPath, data: """
        {"hook": "PostToolUse", "data": {"session_id": "s1", "tool": "Write", "output": "ok"}}
        """)

        try await Task.sleep(nanoseconds: 200_000_000)

        sendToSocket(socketPath: tempSocketPath, data: """
        {"hook": "Stop", "data": {"session_id": "s1"}}
        """)

        try await Task.sleep(nanoseconds: 500_000_000)

        await manager.stopListening()
        task.cancel()

        XCTAssertEqual(receivedEvents.count, 2)

        if case .postToolUse(let sid, let tool, _) = receivedEvents[0] {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(tool, "Write")
        } else {
            XCTFail("Expected postToolUse")
        }

        if case .sessionStop(let sid) = receivedEvents[1] {
            XCTAssertEqual(sid, "s1")
        } else {
            XCTFail("Expected sessionStop")
        }
    }

    func testMalformedDataIsIgnored() async throws {
        let manager = HookManager(hooksDir: tempHooksDir.path, socketPath: tempSocketPath)

        let events = await manager.startListening()
        try await Task.sleep(nanoseconds: 300_000_000)

        var receivedEvents: [HookEvent] = []
        let task = Task {
            for await event in events {
                receivedEvents.append(event)
            }
        }

        // Send garbage data
        sendToSocket(socketPath: tempSocketPath, data: "not json at all")

        // Send valid event after garbage
        try await Task.sleep(nanoseconds: 200_000_000)
        sendToSocket(socketPath: tempSocketPath, data: """
        {"hook": "Notification", "data": {"session_id": "s1", "message": "Done"}}
        """)

        try await Task.sleep(nanoseconds: 500_000_000)

        await manager.stopListening()
        task.cancel()

        // Only the valid event should have been received
        XCTAssertEqual(receivedEvents.count, 1)
        if case .notification(_, let message) = receivedEvents.first {
            XCTAssertEqual(message, "Done")
        } else {
            XCTFail("Expected notification event")
        }
    }

    // MARK: - Helpers

    /// Send data to a Unix domain socket (simulating a hook script).
    private func sendToSocket(socketPath: String, data: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            socketPath.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connected == 0 else { return }

        data.withCString { cstr in
            _ = write(fd, cstr, strlen(cstr))
        }
    }
}
