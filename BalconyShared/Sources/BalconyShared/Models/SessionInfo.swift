import Foundation

/// Metadata about a Claude Code session file.
///
/// Sessions are stored in `~/.claude/projects/{projectHash}/{sessionId}.jsonl`.
/// This struct captures key information for display in the native session picker.
public struct SessionInfo: Codable, Sendable, Identifiable {
    /// Unique session identifier (matches the .jsonl filename without extension).
    public let id: String

    /// Full path to the project directory (e.g., /Users/name/repos/myproject).
    public let projectPath: String

    /// Human-readable title extracted from the first user message or session ID.
    public let title: String

    /// Last modification timestamp of the session file.
    public let lastModified: Date

    /// File size in bytes.
    public let fileSize: Int64

    /// Git branch name if available (extracted from session metadata).
    public let branch: String?

    public init(
        id: String,
        projectPath: String,
        title: String,
        lastModified: Date,
        fileSize: Int64,
        branch: String?
    ) {
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.lastModified = lastModified
        self.fileSize = fileSize
        self.branch = branch
    }

    /// Formatted display name for session picker rows.
    ///
    /// Format: "title · branch · timeAgo"
    /// Example: "Fix login bug · main · 2 hours ago"
    public var displayName: String {
        var parts: [String] = []

        if let branch = branch {
            parts.append(branch)
        }

        parts.append(timeAgo)

        return parts.joined(separator: " · ")
    }

    /// Human-readable time since last modification.
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(lastModified)
        let seconds = Int(interval)

        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if seconds < 2592000 {
            let days = seconds / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let months = seconds / 2592000
            return "\(months) month\(months == 1 ? "" : "s") ago"
        }
    }
}

/// Payload sent from iOS to Mac requesting available sessions for the picker.
public struct SessionPickerRequestPayload: Codable, Sendable {
    /// The PTY session ID where the /resume command was typed.
    public let ptySessionId: String

    public init(ptySessionId: String) {
        self.ptySessionId = ptySessionId
    }
}

/// Payload sent from Mac to iOS when session picker should be shown.
public struct SessionPickerPayload: Codable, Sendable {
    /// The PTY session ID where the /resume command was typed.
    /// iOS echoes this back in the selection payload so Mac routes the command correctly.
    public let ptySessionId: String

    /// Project path for which sessions are listed.
    public let projectPath: String

    /// Available sessions sorted by lastModified (newest first).
    public let sessions: [SessionInfo]

    public init(ptySessionId: String, projectPath: String, sessions: [SessionInfo]) {
        self.ptySessionId = ptySessionId
        self.projectPath = projectPath
        self.sessions = sessions
    }
}

/// Payload sent from iOS to Mac when user selects a session.
public struct SessionPickerSelectionPayload: Codable, Sendable {
    /// Selected Claude Code session identifier to resume.
    public let sessionId: String

    /// The PTY session ID to send the resume command to.
    public let ptySessionId: String

    public init(sessionId: String, ptySessionId: String) {
        self.sessionId = sessionId
        self.ptySessionId = ptySessionId
    }
}
