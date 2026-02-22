import SwiftUI
import BalconyShared

/// Native session picker popup for /resume command.
///
/// Displays available Claude Code sessions filtered by an external search query.
/// Drag the handle down to dismiss.
struct SessionPickerView: View {
    let sessions: [SessionInfo]
    let searchQuery: String
    let onSelect: (SessionInfo) -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var filteredSessions: [SessionInfo] {
        if searchQuery.isEmpty {
            return Array(sessions.prefix(50))
        }
        let lower = searchQuery.lowercased()
        return sessions.filter { session in
            session.title.lowercased().contains(lower) ||
            session.projectPath.lowercased().contains(lower) ||
            (session.branch?.lowercased().contains(lower) ?? false)
        }.prefix(50).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            Divider()
                .background(BalconyTheme.separator)

            // Session list
            if filteredSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSessions) { session in
                            Button {
                                BalconyTheme.hapticLight()
                                onSelect(session)
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 320)
            }
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

            Text("Resume Session")
                .font(BalconyTheme.bodyFont(13))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, BalconyTheme.spacingSM)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            Image(systemName: "ellipsis.bubble")
                .font(.system(size: 16))
                .foregroundStyle(BalconyTheme.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(BalconyTheme.bodyFont(15))
                    .foregroundStyle(BalconyTheme.textPrimary)
                    .lineLimit(1)

                Text(session.displayName)
                    .font(BalconyTheme.bodyFont(13))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: BalconyTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(BalconyTheme.textSecondary)
                .padding(.top, BalconyTheme.spacingXL)

            Text(searchQuery.isEmpty ? "No sessions found" : "No matching sessions")
                .font(BalconyTheme.bodyFont(15))
                .foregroundStyle(BalconyTheme.textSecondary)
                .padding(.bottom, BalconyTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
    }
}

// MARK: - Preview

#Preview {
    let sampleSessions = [
        SessionInfo(
            id: "abc123",
            projectPath: "/Users/name/repos/myproject",
            title: "Fix login bug",
            lastModified: Date().addingTimeInterval(-7200),
            fileSize: 45678,
            branch: "main"
        ),
        SessionInfo(
            id: "def456",
            projectPath: "/Users/name/repos/myproject",
            title: "Add dark mode support",
            lastModified: Date().addingTimeInterval(-86400),
            fileSize: 123456,
            branch: "feature/dark-mode"
        ),
    ]

    return ZStack {
        BalconyTheme.background
            .ignoresSafeArea()

        SessionPickerView(sessions: sampleSessions, searchQuery: "", onSelect: { session in
            print("Selected: \(session.title)")
        }, onDismiss: {
            print("Dismissed")
        })
        .padding()
    }
}
