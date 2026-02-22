import SwiftUI
import BalconyShared

/// Native session picker popup for /resume command.
///
/// Displays available Claude Code sessions with search, formatted display,
/// and haptic feedback. Reuses the FilePickerMenu glass material design.
struct SessionPickerView: View {
    let sessions: [SessionInfo]
    let onSelect: (SessionInfo) -> Void

    @State private var searchQuery = ""

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
            // Search header
            searchField
                .padding(.horizontal, BalconyTheme.spacingMD)
                .padding(.top, BalconyTheme.spacingMD)
                .padding(.bottom, BalconyTheme.spacingSM)

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
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(BalconyTheme.textSecondary)

            TextField("Search sessions...", text: $searchQuery)
                .font(BalconyTheme.bodyFont(15))
                .foregroundStyle(BalconyTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(BalconyTheme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Session Row

    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            // Session icon
            Image(systemName: "ellipsis.bubble")
                .font(.system(size: 16))
                .foregroundStyle(BalconyTheme.accent)
                .frame(width: 28, height: 28)

            // Title and metadata
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

            // Chevron indicator
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

            Text("No sessions found")
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
        SessionInfo(
            id: "ghi789",
            projectPath: "/Users/name/repos/otherproject",
            title: "Refactor authentication system",
            lastModified: Date().addingTimeInterval(-172800),
            fileSize: 234567,
            branch: "main"
        ),
    ]

    return ZStack {
        BalconyTheme.background
            .ignoresSafeArea()

        SessionPickerView(sessions: sampleSessions) { session in
            print("Selected: \(session.title)")
        }
        .padding()
    }
}
