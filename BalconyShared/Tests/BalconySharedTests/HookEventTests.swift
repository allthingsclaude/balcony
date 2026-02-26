import XCTest
@testable import BalconyShared

final class HookEventTests: XCTestCase {

    // MARK: - HookEvent Decoding

    func testDecodeBashPermissionRequest() throws {
        let json = """
        {
          "session_id": "bdd3a905-2a67-41cd-aec5-b4c0e9967258",
          "transcript_path": "/Users/dev/.claude/projects/-Users-dev-repos-myapp/bdd3a905.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "permission_mode": "default",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": {
            "command": "ls -la",
            "description": "List directory contents"
          }
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.hookEventName, "PermissionRequest")
        XCTAssertEqual(event.sessionId, "bdd3a905-2a67-41cd-aec5-b4c0e9967258")
        XCTAssertEqual(event.transcriptPath, "/Users/dev/.claude/projects/-Users-dev-repos-myapp/bdd3a905.jsonl")
        XCTAssertEqual(event.cwd, "/Users/dev/repos/myapp")
        XCTAssertEqual(event.permissionMode, "default")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.toolInput?["command"]?.stringValue, "ls -la")
        XCTAssertEqual(event.toolInput?["description"]?.stringValue, "List directory contents")
    }

    func testDecodeEditPermissionRequest() throws {
        let json = """
        {
          "session_id": "abc-123",
          "transcript_path": "/Users/dev/.claude/projects/test/abc-123.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "permission_mode": "default",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Edit",
          "tool_input": {
            "file_path": "/Users/dev/repos/myapp/src/main.swift",
            "old_string": "let x = 1",
            "new_string": "let x = 2",
            "replace_all": false
          }
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.toolName, "Edit")
        XCTAssertEqual(event.toolInput?["file_path"]?.stringValue, "/Users/dev/repos/myapp/src/main.swift")
        XCTAssertEqual(event.toolInput?["replace_all"]?.boolValue, false)
    }

    func testDecodeWritePermissionRequest() throws {
        let json = """
        {
          "session_id": "write-session-1",
          "transcript_path": "/path/to/transcript.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "permission_mode": "acceptEdits",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Write",
          "tool_input": {
            "file_path": "/Users/dev/repos/myapp/new_file.swift",
            "content": "import Foundation\\nprint(\\"hello\\")"
          }
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.toolName, "Write")
        XCTAssertEqual(event.permissionMode, "acceptEdits")
        XCTAssertEqual(event.toolInput?["file_path"]?.stringValue, "/Users/dev/repos/myapp/new_file.swift")
    }

    func testDecodeGrepWithPathField() throws {
        let json = """
        {
          "session_id": "grep-session",
          "transcript_path": "/path/to/transcript.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "permission_mode": "default",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Grep",
          "tool_input": {
            "pattern": "TODO",
            "path": "/Users/dev/.secrets",
            "output_mode": "files_with_matches"
          }
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.toolName, "Grep")
        // Grep uses "path" not "file_path"
        XCTAssertEqual(event.toolInput?["path"]?.stringValue, "/Users/dev/.secrets")
    }

    func testDecodeMinimalEvent() throws {
        // Only the required fields present
        let json = """
        {
          "hook_event_name": "PermissionRequest",
          "session_id": "minimal-session"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.hookEventName, "PermissionRequest")
        XCTAssertEqual(event.sessionId, "minimal-session")
        XCTAssertNil(event.transcriptPath)
        XCTAssertNil(event.cwd)
        XCTAssertNil(event.permissionMode)
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.toolInput)
    }

    func testDecodeIgnoresUnknownFields() throws {
        // Real events include permission_suggestions and other fields we don't model
        let json = """
        {
          "session_id": "session-1",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": {"command": "echo hi"},
          "permission_suggestions": [{"type": "addRules"}],
          "some_future_field": true
        }
        """.data(using: .utf8)!

        // Should decode without error, ignoring unknown keys
        let event = try JSONDecoder().decode(HookEvent.self, from: json)
        XCTAssertEqual(event.toolName, "Bash")
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = HookEvent(
            hookEventName: "PermissionRequest",
            sessionId: "round-trip-test",
            transcriptPath: "/path/to/transcript.jsonl",
            cwd: "/Users/dev",
            permissionMode: "default",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("ls -la")]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HookEvent.self, from: data)

        XCTAssertEqual(decoded.hookEventName, original.hookEventName)
        XCTAssertEqual(decoded.sessionId, original.sessionId)
        XCTAssertEqual(decoded.transcriptPath, original.transcriptPath)
        XCTAssertEqual(decoded.cwd, original.cwd)
        XCTAssertEqual(decoded.permissionMode, original.permissionMode)
        XCTAssertEqual(decoded.toolName, original.toolName)
        XCTAssertEqual(decoded.toolInput?["command"]?.stringValue, "ls -la")
    }

    // MARK: - PermissionPromptInfo

    func testPermissionPromptInfoFromBashEvent() {
        let event = HookEvent(
            hookEventName: "PermissionRequest",
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("npm install")]
        )

        let info = PermissionPromptInfo.from(event)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.toolName, "Bash")
        XCTAssertEqual(info?.command, "npm install")
        XCTAssertNil(info?.filePath)
        XCTAssertEqual(info?.sessionId, "session-1")
    }

    func testPermissionPromptInfoFromEditEvent() {
        let event = HookEvent(
            hookEventName: "PermissionRequest",
            sessionId: "session-2",
            toolName: "Edit",
            toolInput: ["file_path": AnyCodable("/src/main.swift")]
        )

        let info = PermissionPromptInfo.from(event)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.toolName, "Edit")
        XCTAssertEqual(info?.filePath, "/src/main.swift")
        XCTAssertNil(info?.command)
    }

    func testPermissionPromptInfoFromGrepUsesPathField() {
        let event = HookEvent(
            hookEventName: "PermissionRequest",
            sessionId: "session-3",
            toolName: "Grep",
            toolInput: ["path": AnyCodable("/Users/dev/.secrets")]
        )

        let info = PermissionPromptInfo.from(event)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.filePath, "/Users/dev/.secrets")
    }

    func testPermissionPromptInfoReturnsNilWithoutToolName() {
        let event = HookEvent(
            hookEventName: "PermissionRequest",
            sessionId: "session-4"
        )

        let info = PermissionPromptInfo.from(event)
        XCTAssertNil(info)
    }

    // MARK: - Risk Level

    func testRiskLevelReadIsNormal() {
        let info = PermissionPromptInfo(toolName: "Read", command: nil, filePath: "/file.txt", sessionId: "s")
        XCTAssertEqual(info.riskLevel, .normal)
    }

    func testRiskLevelGlobIsNormal() {
        let info = PermissionPromptInfo(toolName: "Glob", command: nil, filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .normal)
    }

    func testRiskLevelGrepIsNormal() {
        let info = PermissionPromptInfo(toolName: "Grep", command: nil, filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .normal)
    }

    func testRiskLevelBashNonDestructiveIsElevated() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "npm install", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .elevated)
    }

    func testRiskLevelBashNoCommandIsElevated() {
        let info = PermissionPromptInfo(toolName: "Bash", command: nil, filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .elevated)
    }

    func testRiskLevelBashRmIsDestructive() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "rm -rf /tmp/build", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .destructive)
    }

    func testRiskLevelBashSudoIsDestructive() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "sudo apt-get install foo", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .destructive)
    }

    func testRiskLevelBashChmodIsDestructive() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "chmod 777 /etc/passwd", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .destructive)
    }

    func testRiskLevelBashGitForceIsDestructive() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "git push --force origin main", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .destructive)
    }

    func testRiskLevelBashGitResetHardIsDestructive() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "git reset --hard HEAD~3", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .destructive)
    }

    func testRiskLevelBashKillIsDestructive() {
        let info = PermissionPromptInfo(toolName: "Bash", command: "kill -9 12345", filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .destructive)
    }

    func testRiskLevelEditIsElevated() {
        let info = PermissionPromptInfo(toolName: "Edit", command: nil, filePath: "/src/app.swift", sessionId: "s")
        XCTAssertEqual(info.riskLevel, .elevated)
    }

    func testRiskLevelWriteIsElevated() {
        let info = PermissionPromptInfo(toolName: "Write", command: nil, filePath: "/new_file.swift", sessionId: "s")
        XCTAssertEqual(info.riskLevel, .elevated)
    }

    func testRiskLevelUnknownToolIsElevated() {
        let info = PermissionPromptInfo(toolName: "SomeNewTool", command: nil, filePath: nil, sessionId: "s")
        XCTAssertEqual(info.riskLevel, .elevated)
    }

    // MARK: - HookEventPayload

    func testHookEventPayloadFromPermissionPromptInfo() {
        let info = PermissionPromptInfo(
            toolName: "Bash",
            command: "ls -la",
            filePath: nil,
            sessionId: "payload-test"
        )

        let payload = HookEventPayload(from: info)

        XCTAssertEqual(payload.sessionId, "payload-test")
        XCTAssertEqual(payload.toolName, "Bash")
        XCTAssertEqual(payload.command, "ls -la")
        XCTAssertNil(payload.filePath)
        XCTAssertEqual(payload.riskLevel, "elevated")
    }

    func testHookEventPayloadEncodeDecode() throws {
        let payload = HookEventPayload(
            sessionId: "s1",
            toolName: "Edit",
            command: nil,
            filePath: "/src/main.swift",
            riskLevel: "elevated"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HookEventPayload.self, from: data)

        XCTAssertEqual(decoded.sessionId, "s1")
        XCTAssertEqual(decoded.toolName, "Edit")
        XCTAssertNil(decoded.command)
        XCTAssertEqual(decoded.filePath, "/src/main.swift")
        XCTAssertEqual(decoded.riskLevel, "elevated")
    }

    func testHookDismissPayloadEncodeDecode() throws {
        let payload = HookDismissPayload(sessionId: "dismiss-test")

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(HookDismissPayload.self, from: data)

        XCTAssertEqual(decoded.sessionId, "dismiss-test")
    }

    // MARK: - MessageType

    func testHookEventMessageTypeRoundTrip() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let payload = HookEventPayload(
            sessionId: "msg-test",
            toolName: "Bash",
            command: "echo hi",
            filePath: nil,
            riskLevel: "elevated"
        )
        let message = try BalconyMessage.create(type: .hookEvent, payload: payload)
        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.type, .hookEvent)

        let decodedPayload = try decoded.decodePayload(HookEventPayload.self)
        XCTAssertEqual(decodedPayload.toolName, "Bash")
        XCTAssertEqual(decodedPayload.command, "echo hi")
    }

    func testHookDismissMessageTypeRoundTrip() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let payload = HookDismissPayload(sessionId: "dismiss-msg-test")
        let message = try BalconyMessage.create(type: .hookDismiss, payload: payload)
        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.type, .hookDismiss)

        let decodedPayload = try decoded.decodePayload(HookDismissPayload.self)
        XCTAssertEqual(decodedPayload.sessionId, "dismiss-msg-test")
    }

    // MARK: - Stop / Notification Hook Events

    func testDecodeStopEvent() throws {
        let json = """
        {
          "hook_event_name": "Stop",
          "session_id": "stop-session-1",
          "transcript_path": "/path/to/transcript.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "permission_mode": "acceptEdits",
          "stop_hook_active": false,
          "last_assistant_message": "Want me to deploy this so we can see the actual error?"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.hookEventName, "Stop")
        XCTAssertEqual(event.sessionId, "stop-session-1")
        XCTAssertEqual(event.stopHookActive, false)
        XCTAssertEqual(event.lastAssistantMessage, "Want me to deploy this so we can see the actual error?")
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.notificationType)
    }

    func testDecodeNotificationIdlePrompt() throws {
        let json = """
        {
          "hook_event_name": "Notification",
          "session_id": "notif-session-1",
          "transcript_path": "/path/to/transcript.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "message": "Claude is waiting for your input",
          "notification_type": "idle_prompt"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.hookEventName, "Notification")
        XCTAssertEqual(event.notificationType, "idle_prompt")
        XCTAssertEqual(event.message, "Claude is waiting for your input")
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.lastAssistantMessage)
    }

    func testDecodeNotificationPermissionPrompt() throws {
        let json = """
        {
          "hook_event_name": "Notification",
          "session_id": "notif-session-2",
          "transcript_path": "/path/to/transcript.jsonl",
          "cwd": "/Users/dev/repos/myapp",
          "message": "Claude needs your permission to use Bash",
          "notification_type": "permission_prompt"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.notificationType, "permission_prompt")
        XCTAssertEqual(event.message, "Claude needs your permission to use Bash")
    }

    // MARK: - IdlePromptInfo

    func testIdlePromptInfoFromStopEvent() {
        let event = HookEvent(
            hookEventName: "Stop",
            sessionId: "idle-session",
            lastAssistantMessage: "Should I refactor this function?"
        )

        let info = IdlePromptInfo.from(event)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.sessionId, "idle-session")
        XCTAssertEqual(info?.lastAssistantMessage, "Should I refactor this function?")
    }

    func testIdlePromptInfoReturnsNilForNonStopEvent() {
        let event = HookEvent(
            hookEventName: "PermissionRequest",
            sessionId: "perm-session",
            lastAssistantMessage: "some text"
        )

        let info = IdlePromptInfo.from(event)
        XCTAssertNil(info)
    }

    func testIdlePromptInfoReturnsNilForEmptyMessage() {
        let event = HookEvent(
            hookEventName: "Stop",
            sessionId: "empty-session",
            lastAssistantMessage: ""
        )

        let info = IdlePromptInfo.from(event)
        XCTAssertNil(info)
    }

    func testIdlePromptInfoReturnsNilForNilMessage() {
        let event = HookEvent(
            hookEventName: "Stop",
            sessionId: "nil-session"
        )

        let info = IdlePromptInfo.from(event)
        XCTAssertNil(info)
    }

    // MARK: - IdlePromptPayload

    func testIdlePromptPayloadFromInfo() {
        let info = IdlePromptInfo(
            sessionId: "payload-session",
            lastAssistantMessage: "What database should we use?"
        )

        let payload = IdlePromptPayload(from: info)

        XCTAssertEqual(payload.sessionId, "payload-session")
        XCTAssertEqual(payload.lastAssistantMessage, "What database should we use?")
    }

    func testIdlePromptPayloadEncodeDecode() throws {
        let payload = IdlePromptPayload(
            sessionId: "encode-test",
            lastAssistantMessage: "Ready to proceed?"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IdlePromptPayload.self, from: data)

        XCTAssertEqual(decoded.sessionId, "encode-test")
        XCTAssertEqual(decoded.lastAssistantMessage, "Ready to proceed?")
    }

    func testIdlePromptMessageTypeRoundTrip() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let payload = IdlePromptPayload(
            sessionId: "msg-idle-test",
            lastAssistantMessage: "Which approach do you prefer?"
        )
        let message = try BalconyMessage.create(type: .idlePrompt, payload: payload)
        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.type, .idlePrompt)

        let decodedPayload = try decoded.decodePayload(IdlePromptPayload.self)
        XCTAssertEqual(decodedPayload.sessionId, "msg-idle-test")
        XCTAssertEqual(decodedPayload.lastAssistantMessage, "Which approach do you prefer?")
    }

    func testIdlePromptDismissMessageTypeRoundTrip() throws {
        let encoder = MessageEncoder()
        let decoder = MessageDecoder()

        let payload = HookDismissPayload(sessionId: "idle-dismiss-test")
        let message = try BalconyMessage.create(type: .idlePromptDismiss, payload: payload)
        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.type, .idlePromptDismiss)
    }
}
