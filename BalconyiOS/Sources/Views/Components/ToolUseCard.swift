import SwiftUI
import BalconyShared

struct ToolUseCard: View {
    let toolUse: ToolUse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                Text(toolUse.toolName)
                    .font(.headline)
                Spacer()
                Text(toolUse.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            if !toolUse.input.isEmpty {
                Text(toolUse.input)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }

            if let output = toolUse.output {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch toolUse.status {
        case .pending: return "clock"
        case .running: return "gear"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .denied: return "nosign"
        }
    }

    private var statusColor: Color {
        switch toolUse.status {
        case .pending: return .yellow
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .denied: return .orange
        }
    }
}
