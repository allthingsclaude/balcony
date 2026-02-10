import SwiftUI
import BalconyShared

struct SessionCardView: View {
    let session: Session
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            // Project initial avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(dimmed ? 0.3 : 0.15))
                    .frame(width: 40, height: 40)
                Text(projectInitial)
                    .font(BalconyTheme.headingFont(17))
                    .foregroundStyle(avatarColor.opacity(dimmed ? 0.5 : 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                // Top row: project name + status
                HStack {
                    Text(session.projectName)
                        .font(BalconyTheme.headingFont(15))
                        .foregroundStyle(BalconyTheme.textPrimary)
                        .opacity(dimmed ? 0.5 : 1)
                    Spacer()
                    StatusBadge(status: session.status, compact: true)
                }

                // Middle: truncated path
                Text(abbreviatedPath)
                    .font(BalconyTheme.monoFont(11))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .lineLimit(1)
                    .opacity(dimmed ? 0.4 : 0.7)

                // Bottom row: message count + timestamp
                HStack(spacing: BalconyTheme.spacingXS) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(BalconyTheme.textSecondary)
                    Text("\(session.messageCount)")
                        .font(.caption2)
                        .foregroundStyle(BalconyTheme.textSecondary)
                    Spacer()
                    Text(session.lastActivityAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
                .opacity(dimmed ? 0.4 : 0.7)
            }
        }
        .padding(BalconyTheme.spacingMD)
        .background {
            HStack(spacing: 6) {
                if session.status == .active {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BalconyTheme.accent)
                        .frame(width: 3)
                }
                RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                    .fill(BalconyTheme.surfaceSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.projectName), \(session.status.rawValue), \(session.messageCount) messages")
    }

    // MARK: - Helpers

    private var projectInitial: String {
        String(session.projectName.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        switch session.status {
        case .active: return BalconyTheme.accent
        case .idle: return BalconyTheme.statusYellow
        case .completed: return BalconyTheme.textSecondary
        case .error: return BalconyTheme.statusRed
        }
    }

    private var abbreviatedPath: String {
        let path = session.projectPath
        if let homeRange = path.range(of: "/Users/") {
            let afterUsers = path[homeRange.upperBound...]
            if let slashIdx = afterUsers.firstIndex(of: "/") {
                return "~" + String(afterUsers[slashIdx...])
            }
        }
        return path
    }
}
