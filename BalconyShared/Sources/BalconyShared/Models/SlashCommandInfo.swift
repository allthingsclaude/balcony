import Foundation

/// Describes a single slash command available in a Claude Code session.
public struct SlashCommandInfo: Codable, Identifiable, Sendable {
    /// Unique key: the command name (e.g. "debug", "frontend:lint").
    public var id: String { name }

    /// Command name without the leading slash (e.g. "debug").
    public let name: String

    /// Human-readable description from YAML frontmatter.
    public let description: String

    /// Where the command was discovered.
    public let source: Source

    /// Optional hint for expected arguments (e.g. "{NAME} [optional: context]").
    public let argumentHint: String?

    public init(
        name: String,
        description: String,
        source: Source,
        argumentHint: String? = nil
    ) {
        self.name = name
        self.description = description
        self.source = source
        self.argumentHint = argumentHint
    }

    /// Slash-prefixed display name (e.g. "/debug").
    public var displayName: String { "/\(name)" }

    public enum Source: String, Codable, Sendable {
        case builtIn
        case global
        case project

        /// Sort priority: project (0) before global (1) before builtIn (2).
        public var sortPriority: Int {
            switch self {
            case .project: return 0
            case .global: return 1
            case .builtIn: return 2
            }
        }
    }
}

/// Payload for the `slashCommands` message type.
public struct SlashCommandsPayload: Codable, Sendable {
    public let sessionId: String
    public let commands: [SlashCommandInfo]

    public init(sessionId: String, commands: [SlashCommandInfo]) {
        self.sessionId = sessionId
        self.commands = commands
    }
}
