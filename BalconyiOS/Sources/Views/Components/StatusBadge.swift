import SwiftUI
import BalconyShared

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BalconyTheme.textSecondary)
        }
    }

    private var color: Color {
        switch status {
        case .active: return BalconyTheme.statusGreen
        case .idle: return BalconyTheme.statusYellow
        case .completed: return BalconyTheme.textSecondary
        case .error: return BalconyTheme.statusRed
        }
    }

    private var label: String {
        switch status {
        case .active: return "Active"
        case .idle: return "Idle"
        case .completed: return "Done"
        case .error: return "Error"
        }
    }
}
