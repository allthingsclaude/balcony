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
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status {
        case .active: return .green
        case .idle: return .yellow
        case .completed: return .gray
        case .error: return .red
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
