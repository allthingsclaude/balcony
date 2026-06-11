import SwiftUI
import BalconyShared

/// Native rewind picker popup for /rewind command.
///
/// Displays user turn checkpoints computed locally from parsed terminal output,
/// filtered by an external search query. Each entry represents a user input
/// that can be rewound to. Drag the handle down to dismiss.
struct RewindPickerView: View {
    let turns: [RewindTurnInfo]
    let searchQuery: String
    let onSelect: (RewindTurnInfo) -> Void
    let onDismiss: () -> Void

    private var filteredTurns: [RewindTurnInfo] {
        if searchQuery.isEmpty { return turns }
        let lower = searchQuery.lowercased()
        return turns.filter { $0.preview.lowercased().contains(lower) }
    }

    var body: some View {
        PickerScaffold(title: "Rewind", onDismiss: onDismiss) {
            if filteredTurns.isEmpty {
                PickerEmptyState(message: "No matching turns")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTurns) { turn in
                            Button {
                                BalconyTheme.hapticLight()
                                onSelect(turn)
                            } label: {
                                turnRow(turn)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    // MARK: - Turn Row

    private func turnRow(_ turn: RewindTurnInfo) -> some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            // User prompt marker
            Text("\u{203A}")
                .font(BalconyTheme.monoFont(15))
                .foregroundStyle(BalconyTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(turn.preview.isEmpty ? "User input" : turn.preview)
                    .font(BalconyTheme.bodyFont(15))
                    .foregroundStyle(BalconyTheme.textPrimary)
                    .lineLimit(1)

                Text(turnSubtitle(turn))
                    .font(BalconyTheme.bodyFont(13))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(turn.preview.isEmpty ? "User input" : turn.preview), \(turnSubtitle(turn))")
    }

    // MARK: - Helpers

    private func turnSubtitle(_ turn: RewindTurnInfo) -> String {
        if turn.id == 1 {
            return "1 turn ago"
        }
        return "\(turn.id) turns ago"
    }
}

// MARK: - Preview

#Preview {
    let sampleTurns = [
        RewindTurnInfo(id: 1, role: "user", preview: "yeah let's start with /model, plan it out"),
        RewindTurnInfo(id: 2, role: "user", preview: "Analyze how the resume command works on iOS app"),
        RewindTurnInfo(id: 3, role: "user", preview: "/clear"),
    ]

    return ZStack {
        BalconyTheme.background
            .ignoresSafeArea()

        RewindPickerView(
            turns: sampleTurns,
            searchQuery: "",
            onSelect: { turn in print("Selected: \(turn.id) turns") },
            onDismiss: { print("Dismissed") }
        )
        .padding()
    }
}
