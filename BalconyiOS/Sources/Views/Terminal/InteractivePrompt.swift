import Foundation

/// A detected interactive prompt from the terminal that can be answered with native UI.
enum InteractivePrompt: Equatable {
    case permission(PermissionPrompt)
    case multiOption(MultiOptionPrompt)
}

// MARK: - Permission Prompt

/// A tool-permission confirmation like "Allow Read? (Y)es / (N)o / (A)lways".
struct PermissionPrompt: Equatable {
    let options: [PermissionOption]
}

/// A single permission choice.
struct PermissionOption: Equatable, Identifiable {
    let id = UUID()
    let label: String
    /// The character to send (lowercased), e.g. "y", "n", "a".
    let inputToSend: String
    let isDefault: Bool
    let isDestructive: Bool

    static func == (lhs: PermissionOption, rhs: PermissionOption) -> Bool {
        lhs.label == rhs.label &&
        lhs.inputToSend == rhs.inputToSend &&
        lhs.isDefault == rhs.isDefault &&
        lhs.isDestructive == rhs.isDestructive
    }
}

// MARK: - Multi-Option Prompt

/// An AskUserQuestion-style selection list with arrow-key navigation.
struct MultiOptionPrompt: Equatable {
    let question: String
    let options: [MultiOptionItem]
    /// Index of the currently `>`-selected option.
    let selectedIndex: Int
}

/// A single option in a multi-option prompt.
struct MultiOptionItem: Equatable, Identifiable {
    let id = UUID()
    let label: String
    let isRecommended: Bool
    let isOther: Bool
    /// Position in the option list (0-based).
    let index: Int

    static func == (lhs: MultiOptionItem, rhs: MultiOptionItem) -> Bool {
        lhs.label == rhs.label &&
        lhs.isRecommended == rhs.isRecommended &&
        lhs.isOther == rhs.isOther &&
        lhs.index == rhs.index
    }
}
