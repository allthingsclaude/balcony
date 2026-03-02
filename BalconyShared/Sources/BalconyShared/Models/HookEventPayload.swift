import Foundation

/// Payload for forwarding hook events from Mac to iOS via WebSocket.
public struct HookEventPayload: Codable, Sendable {
    /// The PTY session ID this hook event belongs to.
    public let sessionId: String

    /// The tool requesting permission.
    public let toolName: String

    /// The command text for Bash tools.
    public let command: String?

    /// The file path for file operation tools.
    public let filePath: String?

    /// Risk level as a string for cross-platform transport.
    public let riskLevel: String

    /// When the hook event was received.
    public let timestamp: Date

    public init(sessionId: String, toolName: String, command: String?, filePath: String?, riskLevel: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.riskLevel = riskLevel
        self.timestamp = timestamp
    }

    /// Create from a PermissionPromptInfo.
    /// Uses the PTY session ID (what iOS subscribes to) for correct routing/matching.
    public init(from info: PermissionPromptInfo) {
        self.sessionId = info.ptySessionId ?? info.sessionId
        self.toolName = info.toolName
        self.command = info.command
        self.filePath = info.filePath
        self.riskLevel = info.riskLevel.rawValue
        self.timestamp = info.timestamp
    }
}

/// Payload for forwarding idle prompt events (Claude waiting for input) from Mac to iOS.
public struct IdlePromptPayload: Codable, Sendable {
    /// The PTY session ID.
    public let sessionId: String

    /// Claude's last assistant message (the question or summary).
    public let lastAssistantMessage: String

    /// When the idle prompt was detected.
    public let timestamp: Date

    public init(sessionId: String, lastAssistantMessage: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.lastAssistantMessage = lastAssistantMessage
        self.timestamp = timestamp
    }

    /// Create from an IdlePromptInfo.
    /// Uses the PTY session ID (what iOS subscribes to) for correct routing/matching.
    public init(from info: IdlePromptInfo) {
        self.sessionId = info.ptySessionId ?? info.sessionId
        self.lastAssistantMessage = info.lastAssistantMessage
        self.timestamp = info.timestamp
    }
}

/// Payload for dismissing a hook event prompt on iOS.
public struct HookDismissPayload: Codable, Sendable {
    /// The PTY session ID whose prompt was answered.
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

// MARK: - AskUserQuestion Payloads

/// Payload for forwarding AskUserQuestion from Mac to iOS via WebSocket.
public struct AskUserQuestionPayload: Codable, Sendable {
    /// The Claude Code session ID (used in response back to Mac for hook lookup).
    public let sessionId: String

    /// The PTY session ID (matches iOS activeSession.id for routing/matching).
    public let ptySessionId: String?

    /// The structured questions to present to the user.
    public let questions: [Question]

    /// When the question was received.
    public let timestamp: Date

    public struct Question: Codable, Sendable {
        public let question: String
        public let header: String
        public let options: [Option]
        public let multiSelect: Bool

        public struct Option: Codable, Sendable {
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

    public init(sessionId: String, ptySessionId: String?, questions: [Question], timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.ptySessionId = ptySessionId
        self.questions = questions
        self.timestamp = timestamp
    }

    /// Create from an AskUserQuestionInfo.
    public init(from info: AskUserQuestionInfo) {
        self.sessionId = info.sessionId
        self.ptySessionId = info.ptySessionId
        self.questions = info.questions.map { q in
            Question(
                question: q.question,
                header: q.header,
                options: q.options.map { o in
                    Question.Option(label: o.label, description: o.description)
                },
                multiSelect: q.multiSelect
            )
        }
        self.timestamp = info.timestamp
    }
}

/// Payload for dismissing an AskUserQuestion card on iOS.
public struct AskUserQuestionDismissPayload: Codable, Sendable {
    /// The Claude Code session ID.
    public let sessionId: String

    /// The PTY session ID (matches iOS activeSession.id for routing).
    public let ptySessionId: String?

    public init(sessionId: String, ptySessionId: String? = nil) {
        self.sessionId = sessionId
        self.ptySessionId = ptySessionId
    }
}

/// Payload for sending AskUserQuestion answers from iOS to Mac.
public struct AskUserQuestionResponsePayload: Codable, Sendable {
    /// The Claude Code session ID (used by Mac for hook response lookup).
    public let sessionId: String

    /// Answers mapped by question text → selected option label (or custom text).
    public let answers: [String: String]

    public init(sessionId: String, answers: [String: String]) {
        self.sessionId = sessionId
        self.answers = answers
    }
}
