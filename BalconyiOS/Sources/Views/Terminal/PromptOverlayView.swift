import SwiftUI

/// Native overlay for interactive prompts, positioned above the input bar.
/// Shows tappable buttons for permission confirmations and multi-option selections.
struct PromptOverlayView: View {
    let prompt: InteractivePrompt
    let onSendInput: (String) -> Void

    var body: some View {
        switch prompt {
        case .permission(let p):
            PermissionPromptView(prompt: p, onSendInput: onSendInput)
        case .multiOption(let m):
            MultiOptionPromptView(prompt: m, onSendInput: onSendInput)
        }
    }
}

// MARK: - Permission Prompt View

/// Horizontal row of capsule buttons for permission confirmations.
private struct PermissionPromptView: View {
    let prompt: PermissionPrompt
    let onSendInput: (String) -> Void

    var body: some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            ForEach(prompt.options) { option in
                Button {
                    BalconyTheme.hapticMedium()
                    onSendInput(option.inputToSend)
                } label: {
                    HStack(spacing: 4) {
                        Text(option.inputToSend.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .opacity(0.6)
                        Text(option.label)
                            .font(BalconyTheme.bodyFont(14))
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minWidth: 60)
                    .background(optionBackground(option))
                    .foregroundStyle(optionForeground(option))
                    .clipShape(Capsule())
                    .overlay {
                        if !option.isDefault && !option.isDestructive {
                            Capsule()
                                .strokeBorder(BalconyTheme.separator, lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, BalconyTheme.spacingLG)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func optionBackground(_ option: PermissionOption) -> some View {
        if option.isDefault {
            Capsule().fill(BalconyTheme.accent)
        } else if option.isDestructive {
            Capsule().fill(BalconyTheme.statusRed.opacity(0.15))
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }

    private func optionForeground(_ option: PermissionOption) -> Color {
        if option.isDefault {
            return .white
        } else if option.isDestructive {
            return BalconyTheme.statusRed
        } else {
            return BalconyTheme.textPrimary
        }
    }
}

// MARK: - Multi-Option Prompt View

/// Vertical list in a glass-material card for multi-option selections.
private struct MultiOptionPromptView: View {
    let prompt: MultiOptionPrompt
    let onSendInput: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question text
            if !prompt.question.isEmpty {
                Text(prompt.question)
                    .font(BalconyTheme.bodyFont(14))
                    .fontWeight(.medium)
                    .foregroundStyle(BalconyTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }

            Divider()
                .background(BalconyTheme.separator)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(prompt.options) { option in
                        Button {
                            BalconyTheme.hapticMedium()
                            sendOptionSelection(option)
                        } label: {
                            optionRow(option)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
        }
        .background {
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
        }
        .clipShape(RoundedRectangle(cornerRadius: BalconyTheme.radiusMD))
        .padding(.horizontal, BalconyTheme.spacingLG)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Option Row

    private func optionRow(_ option: MultiOptionItem) -> some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            // Selection indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(option.index == prompt.selectedIndex ? BalconyTheme.accent : Color.clear)
                .frame(width: 3, height: 20)

            Text(option.label)
                .font(BalconyTheme.bodyFont(14))
                .foregroundStyle(
                    option.index == prompt.selectedIndex
                        ? BalconyTheme.textPrimary
                        : BalconyTheme.textSecondary
                )
                .fontWeight(option.index == prompt.selectedIndex ? .medium : .regular)

            if option.isRecommended {
                Text("Recommended")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(BalconyTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(BalconyTheme.accentSubtle, in: Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Input Sending

    /// Navigate to the target option using arrow keys, then confirm with Enter.
    private func sendOptionSelection(_ option: MultiOptionItem) {
        let delta = option.index - prompt.selectedIndex

        if delta != 0 {
            // Send arrow keys to navigate.
            let arrowKey = delta > 0 ? "\u{1b}[B" : "\u{1b}[A"
            let keyCount = abs(delta)
            let arrows = String(repeating: arrowKey, count: keyCount)
            onSendInput(arrows)
        }

        // Small delay to let the terminal process arrow keys, then confirm.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            onSendInput("\r")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Permission Prompt") {
    ZStack {
        BalconyTheme.background.ignoresSafeArea()
        VStack {
            Spacer()
            PromptOverlayView(
                prompt: .permission(PermissionPrompt(options: [
                    PermissionOption(label: "Yes", inputToSend: "y", isDefault: true, isDestructive: false),
                    PermissionOption(label: "No", inputToSend: "n", isDefault: false, isDestructive: true),
                    PermissionOption(label: "Always allow", inputToSend: "a", isDefault: false, isDestructive: false),
                ])),
                onSendInput: { _ in }
            )
            .padding(.bottom, 80)
        }
    }
}

#Preview("Multi-Option Prompt") {
    ZStack {
        BalconyTheme.background.ignoresSafeArea()
        VStack {
            Spacer()
            PromptOverlayView(
                prompt: .multiOption(MultiOptionPrompt(
                    question: "Which approach do you prefer?",
                    options: [
                        MultiOptionItem(label: "Use Redux", isRecommended: true, isOther: false, index: 0),
                        MultiOptionItem(label: "Use Context API", isRecommended: false, isOther: false, index: 1),
                        MultiOptionItem(label: "Use Zustand", isRecommended: false, isOther: false, index: 2),
                        MultiOptionItem(label: "Other", isRecommended: false, isOther: true, index: 3),
                    ],
                    selectedIndex: 0
                )),
                onSendInput: { _ in }
            )
            .padding(.bottom, 80)
        }
    }
}
#endif
