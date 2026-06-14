import Foundation

/// A single content block inside a transcript event, mirroring Claude Code's
/// JSONL message-content blocks but stripped to what the iOS transcript renders.
///
/// Base64 image payloads from `tool_result` blocks are never carried here — they
/// are collapsed to `.image(altText:)` placeholders so the wire stays small.
public enum TranscriptBlock: Sendable, Equatable {
    /// Plain prose / markdown from an assistant or user message.
    case text(String)
    /// Extended-thinking content (assistant only).
    case thinking(String)
    /// An assistant tool invocation. `input` is a one-line human summary
    /// (e.g. the Bash command or the file path), not the raw JSON.
    case toolUse(id: String, name: String, input: String)
    /// The result of a tool call, keyed back to its `toolUse` by `toolUseID`.
    case toolResult(toolUseID: String, text: String, isError: Bool)
    /// A placeholder for an image (pasted by the user or returned by a tool).
    case image(altText: String)
}

// MARK: - Codable

extension TranscriptBlock: Codable {
    private enum Kind: String, Codable {
        case text, thinking, toolUse, toolResult, image
    }

    private enum CodingKeys: String, CodingKey {
        case kind, text, id, name, input, toolUseID, isError, altText
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode(Kind.text, forKey: .kind)
            try c.encode(t, forKey: .text)
        case .thinking(let t):
            try c.encode(Kind.thinking, forKey: .kind)
            try c.encode(t, forKey: .text)
        case .toolUse(let id, let name, let input):
            try c.encode(Kind.toolUse, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let text, let isError):
            try c.encode(Kind.toolResult, forKey: .kind)
            try c.encode(toolUseID, forKey: .toolUseID)
            try c.encode(text, forKey: .text)
            try c.encode(isError, forKey: .isError)
        case .image(let altText):
            try c.encode(Kind.image, forKey: .kind)
            try c.encode(altText, forKey: .altText)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))
        case .thinking:
            self = .thinking(try c.decode(String.self, forKey: .text))
        case .toolUse:
            self = .toolUse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                input: try c.decode(String.self, forKey: .input)
            )
        case .toolResult:
            self = .toolResult(
                toolUseID: try c.decode(String.self, forKey: .toolUseID),
                text: try c.decode(String.self, forKey: .text),
                isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            )
        case .image:
            self = .image(altText: try c.decode(String.self, forKey: .altText))
        }
    }
}

// MARK: - TranscriptEvent

/// A user or assistant turn extracted from a Claude Code session's JSONL
/// transcript — the *structured* source of truth, in contrast to the
/// reconstructed PTY screen scrape.
///
/// One JSONL `user`/`assistant` record maps to one `TranscriptEvent`.
/// `id` is the record's `uuid`, so events are stable and de-dupable across
/// re-reads of the file (e.g. after the Mac re-snapshots on truncation).
public struct TranscriptEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    /// The JSONL record `uuid` — stable identity for diffing/de-duping.
    public let id: String
    public let role: Role
    public let blocks: [TranscriptBlock]
    public let timestamp: Date?
    /// True for sub-agent (Task tool) entries, which the main transcript hides.
    public let isSidechain: Bool

    public init(
        id: String,
        role: Role,
        blocks: [TranscriptBlock],
        timestamp: Date? = nil,
        isSidechain: Bool = false
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.timestamp = timestamp
        self.isSidechain = isSidechain
    }
}
