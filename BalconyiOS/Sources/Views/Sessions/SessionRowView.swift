import SwiftUI
import BalconyShared

struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.projectName)
                    .font(BalconyTheme.headingFont())
                    .foregroundStyle(BalconyTheme.textPrimary)
                Spacer()
                StatusBadge(status: session.status)
            }

            HStack {
                Text("\(session.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(BalconyTheme.textSecondary)
                Spacer()
                Text(session.lastActivityAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(BalconyTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
