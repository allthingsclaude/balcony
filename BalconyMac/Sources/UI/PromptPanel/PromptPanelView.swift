import SwiftUI
import BalconyShared

/// SwiftUI view for the floating permission prompt panel.
struct PromptPanelView: View {
    let info: PermissionPromptInfo
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: tool icon + name + risk badge
            headerRow

            // Body: command or file path preview
            if let command = info.command, !command.isEmpty {
                commandPreview(command)
            } else if let filePath = info.filePath, !filePath.isEmpty {
                filePathPreview(filePath)
            }

            Divider()

            // Footer: action buttons
            actionButtons
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: toolIconName)
                .font(.title3)
                .foregroundStyle(riskColor)
                .frame(width: 24, height: 24)

            Text(info.toolName)
                .font(.headline)

            Spacer()

            riskBadge
        }
    }

    private var riskBadge: some View {
        Text(riskLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor.opacity(0.15))
            .foregroundStyle(riskColor)
            .clipShape(Capsule())
    }

    // MARK: - Command / File Preview

    private func commandPreview(_ command: String) -> some View {
        let displayCommand = command.count > 300
            ? String(command.prefix(300)) + "..."
            : command

        return Text(displayCommand)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func filePathPreview(_ filePath: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(filePath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: { onAction("n") }) {
                Text("Deny")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button(action: { onAction("y") }) {
                Text("Allow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    // MARK: - Computed Properties

    private var toolIconName: String {
        switch info.toolName {
        case "Bash":
            return "terminal"
        case "Edit":
            return "pencil.line"
        case "Write":
            return "doc.badge.plus"
        case "Read":
            return "doc.text.magnifyingglass"
        case "Glob":
            return "folder.badge.questionmark"
        case "Grep":
            return "magnifyingglass"
        case "Task":
            return "arrow.triangle.branch"
        default:
            return "gearshape"
        }
    }

    private var riskColor: Color {
        switch info.riskLevel {
        case .normal:
            return .green
        case .elevated:
            return .yellow
        case .destructive:
            return .red
        }
    }

    private var riskLabel: String {
        switch info.riskLevel {
        case .normal:
            return "Low Risk"
        case .elevated:
            return "Elevated"
        case .destructive:
            return "Destructive"
        }
    }
}
