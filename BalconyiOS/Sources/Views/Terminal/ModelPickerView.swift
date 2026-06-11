import SwiftUI
import BalconyShared

/// Native model picker popup for /model command.
///
/// Displays available Claude models sorted by tier with the current model highlighted.
/// Drag the handle down to dismiss.
struct ModelPickerView: View {
    let models: [ModelInfo]
    let currentModelId: String?
    let onSelect: (ModelInfo) -> Void
    let onDismiss: () -> Void

    /// Models sorted by tier — Opus first, Haiku last.
    private var sortedModels: [ModelInfo] {
        models.sorted { $0.tier < $1.tier }
    }

    var body: some View {
        PickerScaffold(title: "Switch Model", onDismiss: onDismiss) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedModels) { model in
                        Button {
                            BalconyTheme.hapticLight()
                            onSelect(model)
                        } label: {
                            modelRow(model)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
    }

    // MARK: - Model Row

    private func modelRow(_ model: ModelInfo) -> some View {
        let isActive = isCurrentModel(model)

        return HStack(spacing: BalconyTheme.spacingMD) {
            Image(systemName: tierIcon(model.tier))
                .font(.system(size: 13))
                .foregroundStyle(BalconyTheme.textSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(BalconyTheme.bodyFont(15))
                    .foregroundStyle(BalconyTheme.textPrimary)
                    .lineLimit(1)

                Text(model.description)
                    .font(BalconyTheme.bodyFont(13))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(BalconyTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: BalconyTheme.radiusSM)
                    .fill(BalconyTheme.accent.opacity(0.08))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName), \(model.description)\(isActive ? ", current model" : "")")
    }

    // MARK: - Helpers

    /// Check if a model matches the current model ID using contains for fuzzy matching,
    /// since JSONL model IDs may include date suffixes or differ slightly.
    private func isCurrentModel(_ model: ModelInfo) -> Bool {
        guard let currentId = currentModelId else { return false }
        return currentId.contains(model.id) || model.id.contains(currentId)
    }

    private func tierIcon(_ tier: ModelTier) -> String {
        switch tier {
        case .opus: return "brain.head.profile"
        case .sonnet: return "bolt.fill"
        case .haiku: return "leaf.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleModels = [
        ModelInfo(
            id: "opus",
            displayName: "Opus",
            description: "Most capable — deep reasoning and complex tasks",
            tier: .opus
        ),
        ModelInfo(
            id: "sonnet",
            displayName: "Sonnet",
            description: "Balanced speed and intelligence",
            tier: .sonnet
        ),
        ModelInfo(
            id: "haiku",
            displayName: "Haiku",
            description: "Fast and lightweight for quick tasks",
            tier: .haiku
        ),
    ]

    return ZStack {
        BalconyTheme.background
            .ignoresSafeArea()

        ModelPickerView(
            models: sampleModels,
            currentModelId: "claude-sonnet-4-20250514",
            onSelect: { model in print("Selected: \(model.displayName)") },
            onDismiss: { print("Dismissed") }
        )
        .padding()
    }
}
