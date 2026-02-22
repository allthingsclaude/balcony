import SwiftUI
import BalconyShared

/// Native rewind picker popup for /rewind command.
///
/// Displays user turn checkpoints computed locally from parsed terminal output.
/// Each entry represents a user input that can be rewound to.
/// Drag the handle down to dismiss.
struct RewindPickerView: View {
    let turns: [RewindTurnInfo]
    let onSelect: (RewindTurnInfo) -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            Divider()
                .background(BalconyTheme.separator)

            // Turn list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(turns) { turn in
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
        .background {
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
        }
        .clipShape(RoundedRectangle(cornerRadius: BalconyTheme.radiusMD))
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 160 {
                        BalconyTheme.hapticLight()
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(BalconyTheme.textSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Rewind")
                .font(BalconyTheme.bodyFont(13))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, BalconyTheme.spacingSM)
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
            onSelect: { turn in print("Selected: \(turn.id) turns") },
            onDismiss: { print("Dismissed") }
        )
        .padding()
    }
}
