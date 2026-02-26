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

    /// Current working directory of the Claude Code session.
    public let cwd: String?

    /// The tool requesting permission (e.g., "Bash", "Edit", "Write", "Read").
    public let toolName: String?

    /// Tool-specific input parameters as raw JSON.
    public let toolInput: [String: AnyCodable]?

    public init(
        hookEventName: String,
        sessionId: String,
        cwd: String? = nil,
        toolName: String? = nil,
        toolInput: [String: AnyCodable]? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
    }

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
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

    /// The session ID this prompt belongs to.
    public let sessionId: String

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

    public init(toolName: String, command: String?, filePath: String?, sessionId: String, timestamp: Date = Date()) {
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.sessionId = sessionId
        self.timestamp = timestamp
    }

    /// Create from a raw HookEvent.
    public static func from(_ event: HookEvent) -> PermissionPromptInfo? {
        guard let toolName = event.toolName else { return nil }

        let command = event.toolInput?["command"]?.stringValue
        let filePath = event.toolInput?["file_path"]?.stringValue
            ?? event.toolInput?["filePath"]?.stringValue
            ?? event.toolInput?["path"]?.stringValue

        return PermissionPromptInfo(
            toolName: toolName,
            command: command,
            filePath: filePath,
            sessionId: event.sessionId
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
