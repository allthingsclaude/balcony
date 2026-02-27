import Foundation

/// Risk level of a tool permission request.
public enum ToolRiskLevel: String, Codable, Sendable {
    case normal
    case elevated
    case destructive
}

/// A hook event received from Claude Code's hooks system.
///
/// Claude Code pipes JSON to the hook handler's stdin with tool invocation
/// details. Fields use snake_case in the wire format.
public struct HookEvent: Codable, Sendable {
    /// The hook event type (e.g., "PermissionRequest", "PreToolUse").
    public let hookEventName: String

    /// The Claude Code session ID.
    public let sessionId: String

    /// Absolute path to the session's JSONL transcript file.
    public let transcriptPath: String?

    /// Current working directory of the Claude Code session.
    public let cwd: String?

    /// Current permission mode (e.g., "default", "acceptEdits").
    public let permissionMode: String?

    /// The tool requesting permission (e.g., "Bash", "Edit", "Write", "Read").
    public let toolName: String?

    /// Tool-specific input parameters as raw JSON.
    public let toolInput: [String: AnyCodable]?

    /// The full text of Claude's last assistant message (Stop events only).
    public let lastAssistantMessage: String?

    /// Human-readable notification text (Notification events only).
    public let message: String?

    /// Notification category (Notification events only): "idle_prompt" or "permission_prompt".
    public let notificationType: String?

    /// Whether this Stop was triggered by another Stop hook (anti-recursion guard).
    public let stopHookActive: Bool?

    /// PTY session ID injected by BalconyCLI wrapper (nil if not running through wrapper).
    public let balconyPtySessionId: String?

    public init(
        hookEventName: String,
        sessionId: String,
        transcriptPath: String? = nil,
        cwd: String? = nil,
        permissionMode: String? = nil,
        toolName: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        lastAssistantMessage: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        stopHookActive: Bool? = nil,
        balconyPtySessionId: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.toolInput = toolInput
        self.lastAssistantMessage = lastAssistantMessage
        self.message = message
        self.notificationType = notificationType
        self.stopHookActive = stopHookActive
        self.balconyPtySessionId = balconyPtySessionId
    }

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case lastAssistantMessage = "last_assistant_message"
        case message
        case notificationType = "notification_type"
        case stopHookActive = "stop_hook_active"
        case balconyPtySessionId = "balcony_pty_session_id"
    }
}

// MARK: - Parsed Permission Info

/// Structured information about a permission prompt, parsed from a HookEvent.
public struct PermissionPromptInfo: Sendable {
    /// The tool name (e.g., "Bash", "Edit", "Write").
    public let toolName: String

    /// The command text for Bash tools.
    public let command: String?

    /// The file path for file operation tools (Edit, Write, Read).
    public let filePath: String?

    /// Additional tool-specific detail (URL, query, pattern, description).
    public let detail: String?

    /// The Claude Code session ID this prompt belongs to.
    public let sessionId: String

    /// The working directory of the Claude Code session (used to resolve PTY session).
    public let cwd: String?

    /// Direct PTY session ID from BalconyCLI wrapper (nil if not wrapped).
    public let ptySessionId: String?

    /// When this prompt was received.
    public let timestamp: Date

    /// Computed risk level based on tool and command content.
    public var riskLevel: ToolRiskLevel {
        switch toolName {
        case "Read", "Glob", "Grep":
            return .normal
        case "Bash":
            guard let cmd = command else { return .elevated }
            let destructivePatterns = [
                "rm ", "rm\t", "rmdir",
                "sudo ", "chmod ", "chown ",
                "mkfs", "dd ",
                "git push --force", "git reset --hard",
                "> /dev/", "kill ", "killall ",
                "mv /", "cp /",
            ]
            for pattern in destructivePatterns {
                if cmd.contains(pattern) { return .destructive }
            }
            return .elevated
        case "Edit", "Write":
            return .elevated
        default:
            return .elevated
        }
    }

    public init(toolName: String, command: String?, filePath: String?, detail: String? = nil, sessionId: String, cwd: String? = nil, ptySessionId: String? = nil, timestamp: Date = Date()) {
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.detail = detail
        self.sessionId = sessionId
        self.cwd = cwd
        self.ptySessionId = ptySessionId
        self.timestamp = timestamp
    }

    /// Create from a raw HookEvent.
    public static func from(_ event: HookEvent) -> PermissionPromptInfo? {
        guard let toolName = event.toolName else { return nil }

        let input = event.toolInput
        let command = input?["command"]?.stringValue
        let filePath = input?["file_path"]?.stringValue
            ?? input?["filePath"]?.stringValue
            ?? input?["path"]?.stringValue

        // Extract tool-specific detail: URL, query, pattern, description, etc.
        let detail: String? = input?["url"]?.stringValue
            ?? input?["query"]?.stringValue
            ?? input?["pattern"]?.stringValue
            ?? input?["description"]?.stringValue
            ?? input?["prompt"]?.stringValue

        return PermissionPromptInfo(
            toolName: toolName,
            command: command,
            filePath: filePath,
            detail: detail,
            sessionId: event.sessionId,
            cwd: event.cwd,
            ptySessionId: event.balconyPtySessionId
        )
    }
}

// MARK: - Idle Prompt Info

/// Structured information about Claude stopping and waiting for user input.
/// Created by correlating a `Stop` hook event with a `Notification(idle_prompt)` event.
public struct IdlePromptInfo: Sendable {
    /// The Claude Code session ID this idle prompt belongs to.
    public let sessionId: String

    /// Claude's last assistant message (the question or completion text).
    public let lastAssistantMessage: String

    /// The working directory of the Claude Code session (used to resolve PTY session).
    public let cwd: String?

    /// Direct PTY session ID from BalconyCLI wrapper (nil if not wrapped).
    public let ptySessionId: String?

    /// When this idle prompt was detected.
    public let timestamp: Date

    public init(sessionId: String, lastAssistantMessage: String, cwd: String? = nil, ptySessionId: String? = nil, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.lastAssistantMessage = lastAssistantMessage
        self.cwd = cwd
        self.ptySessionId = ptySessionId
        self.timestamp = timestamp
    }

    /// Create from a Stop hook event.
    public static func from(_ event: HookEvent) -> IdlePromptInfo? {
        guard event.hookEventName == "Stop",
              let message = event.lastAssistantMessage,
              !message.isEmpty else { return nil }
        return IdlePromptInfo(
            sessionId: event.sessionId,
            lastAssistantMessage: message,
            cwd: event.cwd
        )
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for heterogeneous JSON values.
public struct AnyCodable: Codable, Sendable {
    public let value: Any & Sendable

    public init(_ value: Any & Sendable) {
        self.value = value
    }

    /// Extract as String if the underlying value is a string.
    public var stringValue: String? {
        value as? String
    }

    /// Extract as Int if the underlying value is numeric.
    public var intValue: Int? {
        value as? Int
    }

    /// Extract as Bool if the underlying value is boolean.
    public var boolValue: Bool? {
        value as? Bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value) as [Any]
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value) as [String: Any]
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [any Sendable]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: any Sendable]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
