import Foundation

/// Tier classification for Claude models.
public enum ModelTier: String, Codable, Sendable, Comparable {
    case opus
    case sonnet
    case haiku

    /// Sort priority — Opus first, Haiku last.
    private var sortOrder: Int {
        switch self {
        case .opus: return 0
        case .sonnet: return 1
        case .haiku: return 2
        }
    }

    public static func < (lhs: ModelTier, rhs: ModelTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Metadata about a Claude model available in Claude Code.
public struct ModelInfo: Codable, Sendable, Identifiable {
    /// The exact model ID that Claude Code expects (e.g., "claude-sonnet-4-20250514").
    public let id: String

    /// Human-readable display name (e.g., "Claude Sonnet 4").
    public let displayName: String

    /// Short description of the model's strengths.
    public let description: String

    /// Model tier for grouping and sorting.
    public let tier: ModelTier

    public init(id: String, displayName: String, description: String, tier: ModelTier) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.tier = tier
    }
}

/// Payload sent from iOS to Mac requesting the model picker.
public struct ModelPickerRequestPayload: Codable, Sendable {
    /// The PTY session ID where the /model command was typed.
    public let ptySessionId: String

    public init(ptySessionId: String) {
        self.ptySessionId = ptySessionId
    }
}

/// Payload sent from Mac to iOS when model picker should be shown.
public struct ModelPickerPayload: Codable, Sendable {
    /// The PTY session ID where the /model command was typed.
    /// iOS echoes this back in the selection payload so Mac routes the command correctly.
    public let ptySessionId: String

    /// The currently active model ID (if detected from session JSONL).
    public let currentModelId: String?

    /// Available models to choose from.
    public let models: [ModelInfo]

    public init(ptySessionId: String, currentModelId: String?, models: [ModelInfo]) {
        self.ptySessionId = ptySessionId
        self.currentModelId = currentModelId
        self.models = models
    }
}

/// Payload sent from iOS to Mac when user selects a model.
public struct ModelPickerSelectionPayload: Codable, Sendable {
    /// The selected model ID to switch to.
    public let modelId: String

    /// The PTY session ID to send the model command to.
    public let ptySessionId: String

    public init(modelId: String, ptySessionId: String) {
        self.modelId = modelId
        self.ptySessionId = ptySessionId
    }
}
