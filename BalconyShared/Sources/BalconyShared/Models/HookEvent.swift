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

    /// PID of the hook handler process (injected by HookListener, not from JSON).
    public var hookPeerPID: Int32? = nil

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

    /// PID of the hook handler process (for process-tree based PTY resolution).
    public let hookPeerPID: Int32?

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

    public init(toolName: String, command: String?, filePath: String?, detail: String? = nil, sessionId: String, cwd: String? = nil, ptySessionId: String? = nil, hookPeerPID: Int32? = nil, timestamp: Date = Date()) {
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.detail = detail
        self.sessionId = sessionId
        self.cwd = cwd
        self.ptySessionId = ptySessionId
        self.hookPeerPID = hookPeerPID
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
            ptySessionId: event.balconyPtySessionId,
            hookPeerPID: event.hookPeerPID
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

    /// PID of the hook handler process (for process-tree based PTY resolution).
    public let hookPeerPID: Int32?

    public init(sessionId: String, lastAssistantMessage: String, cwd: String? = nil, ptySessionId: String? = nil, hookPeerPID: Int32? = nil, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.lastAssistantMessage = lastAssistantMessage
        self.cwd = cwd
        self.ptySessionId = ptySessionId
        self.hookPeerPID = hookPeerPID
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
            cwd: event.cwd,
            hookPeerPID: event.hookPeerPID
        )
    }

    /// Detect if the assistant message contains an AskUserQuestion-style option list.
    /// Returns nil if it's a plain text prompt or a regular numbered list.
    public var detectedOptions: (question: String, options: [ParsedOption])? {
        let lines = lastAssistantMessage.components(separatedBy: .newlines)

        // Scan backwards to find the numbered options block
        var optionLines: [(index: Int, label: String)] = []
        var scanIndex = lines.count - 1

        // Skip trailing empty lines
        while scanIndex >= 0 && lines[scanIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            scanIndex -= 1
        }

        // Collect numbered lines (e.g., "1. Option A", "2. Option B")
        let optionPattern = #"^\s*(\d+)\.\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: optionPattern) else { return nil }

        while scanIndex >= 0 {
            let line = lines[scanIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex.firstMatch(in: trimmed, range: range),
               let numRange = Range(match.range(at: 1), in: trimmed),
               let labelRange = Range(match.range(at: 2), in: trimmed),
               let num = Int(trimmed[numRange]) {
                let label = String(trimmed[labelRange])
                optionLines.insert((index: num, label: label), at: 0)
                scanIndex -= 1
            } else {
                break
            }
        }

        // Require at least 2 options
        guard optionLines.count >= 2 else { return nil }

        // Validate sequential numbering starting from 1
        for (i, option) in optionLines.enumerated() {
            guard option.index == i + 1 else { return nil }
        }

        // Reject regular numbered lists: options should be short, plain labels
        // (not full sentences with markdown, em dashes, or long descriptions)
        for item in optionLines {
            // Real options are concise (typically under 80 chars)
            if item.label.count > 80 { return nil }
            // Markdown formatting indicates a description, not a selectable option
            if item.label.contains("**") || item.label.contains("``") { return nil }
            // Em dashes or long separators indicate descriptive list items
            if item.label.contains(" — ") || item.label.contains(" -- ") { return nil }
        }

        // Extract the question text (everything before the options block)
        let questionLines = lines.prefix(scanIndex + 1)
        let question = questionLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !question.isEmpty else { return nil }

        // Build ParsedOption array
        let options = optionLines.map { item in
            let isOther = item.label.lowercased().hasPrefix("other")
            return ParsedOption(index: item.index, label: item.label, isOther: isOther)
        }

        return (question: question, options: options)
    }
}

// MARK: - ParsedOption

/// A detected option from an AskUserQuestion-style prompt.
public struct ParsedOption: Sendable {
    /// 1-based index of the option.
    public let index: Int
    /// Display label (e.g., "Option A (Recommended)").
    public let label: String
    /// Whether this is the "Other" free-text option.
    public let isOther: Bool

    public init(index: Int, label: String, isOther: Bool) {
        self.index = index
        self.label = label
        self.isOther = isOther
    }
}

// MARK: - AskUserQuestionInfo

/// Structured information about an AskUserQuestion tool call, parsed from toolInput.
public struct AskUserQuestionInfo: Sendable {
    public struct Question: Sendable {
        public let question: String
        public let header: String
        public let options: [Option]
        public let multiSelect: Bool

        public struct Option: Sendable {
            public let label: String
            public let description: String?

            public init(label: String, description: String?) {
                self.label = label
                self.description = description
            }
        }

        public init(question: String, header: String, options: [Option], multiSelect: Bool) {
            self.question = question
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    public let sessionId: String
    public let questions: [Question]
    public let cwd: String?
    public let ptySessionId: String?
    public let hookPeerPID: Int32?
    public let timestamp: Date

    /// Original toolInput from the hook event — passed through in the updatedInput response.
    public let toolInput: [String: AnyCodable]?

    public init(sessionId: String, questions: [Question], cwd: String?, ptySessionId: String?, hookPeerPID: Int32? = nil, toolInput: [String: AnyCodable]? = nil, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.questions = questions
        self.cwd = cwd
        self.ptySessionId = ptySessionId
        self.hookPeerPID = hookPeerPID
        self.toolInput = toolInput
        self.timestamp = timestamp
    }

    /// Create from a PermissionRequest hook event for the AskUserQuestion tool.
    public static func from(_ event: HookEvent) -> AskUserQuestionInfo? {
        guard event.toolName == "AskUserQuestion",
              let input = event.toolInput,
              let questionsValue = input["questions"]?.value as? [Any] else { return nil }

        var questions: [Question] = []
        for qAny in questionsValue {
            guard let q = qAny as? [String: Any],
                  let questionText = q["question"] as? String,
                  let header = q["header"] as? String,
                  let optionsValue = q["options"] as? [Any] else { continue }

            let multiSelect = q["multiSelect"] as? Bool ?? false
            var options: [Question.Option] = []
            for optAny in optionsValue {
                guard let opt = optAny as? [String: Any],
                      let label = opt["label"] as? String else { continue }
                options.append(Question.Option(label: label, description: opt["description"] as? String))
            }

            guard options.count >= 2 else { continue }
            questions.append(Question(question: questionText, header: header, options: options, multiSelect: multiSelect))
        }

        guard !questions.isEmpty else { return nil }
        return AskUserQuestionInfo(
            sessionId: event.sessionId,
            questions: questions,
            cwd: event.cwd,
            ptySessionId: event.balconyPtySessionId,
            hookPeerPID: event.hookPeerPID,
            toolInput: input,
            timestamp: Date()
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
