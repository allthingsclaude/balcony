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
        PickerScaffold(title: "Resume Session", onDismiss: onDismiss) {
            if filteredSessions.isEmpty {
                PickerEmptyState(
                    message: searchQuery.isEmpty ? "No sessions found" : "No matching sessions"
                )
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
    }

    // MARK: - Session Row

    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            Image(systemName: "ellipsis.bubble")
                .font(.system(size: 14))
                .foregroundStyle(BalconyTheme.accent)
                .frame(width: 24, height: 24)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.displayName)")
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
