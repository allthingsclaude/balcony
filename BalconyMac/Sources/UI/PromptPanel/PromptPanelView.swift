import SwiftUI
import BalconyShared

/// SwiftUI view for the floating permission prompt panel.
struct PromptPanelView: View {
    let info: PermissionPromptInfo
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: tool icon + name + risk badge
            headerRow

            // Project directory
            if let projectName = projectName {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(projectName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Body: command, file path, or detail preview
            if let command = info.command, !command.isEmpty {
                commandPreview(command)
            } else if let filePath = info.filePath, !filePath.isEmpty {
                filePathPreview(filePath)
            } else if let detail = info.detail, !detail.isEmpty {
                detailPreview(detail)
            }

            Divider()

            // Footer: action buttons
            actionButtons
        }
        .padding(16)
        .frame(width: 340)
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

    // MARK: - Project Name

    private var projectName: String? {
        guard let cwd = info.cwd else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    // MARK: - Command / File / Detail Preview

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
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func filePathPreview(_ filePath: String) -> some View {
        let displayPath = abbreviatePath(filePath)
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func detailPreview(_ detail: String) -> some View {
        let displayDetail = detail.count > 300
            ? String(detail.prefix(300)) + "..."
            : detail

        return Text(displayDetail)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.black.opacity(0.06))
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

            Button(action: { onAction("a") }) {
                Text("Always")
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

    // MARK: - Helpers

    /// Abbreviate a file path relative to cwd if possible.
    private func abbreviatePath(_ path: String) -> String {
        if let cwd = info.cwd, path.hasPrefix(cwd) {
            let relative = String(path.dropFirst(cwd.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        // Abbreviate home directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
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
        case "WebFetch":
            return "globe"
        case "WebSearch":
            return "magnifyingglass.circle"
        case "NotebookEdit":
            return "book"
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

// MARK: - Idle Prompt Panel View

/// SwiftUI view for the floating idle prompt panel (Claude waiting for input).
/// Shows Claude's last message with a text field for the user to respond.
struct IdlePromptPanelView: View {
    let info: IdlePromptInfo
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var responseText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title3)
                    .foregroundStyle(Color.blue)
                    .frame(width: 24, height: 24)

                Text("Claude is waiting")
                    .font(.headline)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Project directory
            if let projectName = projectName {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(projectName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Claude's message
            Text(displayMessage)
                .font(.system(.caption, design: .default))
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()

            // Text input + submit
            HStack(spacing: 8) {
                TextField("Type a response...", text: $responseText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default))
                    .focused($textFieldFocused)
                    .onSubmit { submitResponse() }
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button(action: submitResponse) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(responseText.isEmpty ? .secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(responseText.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .onAppear { textFieldFocused = true }
    }

    private var projectName: String? {
        guard let cwd = info.cwd else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private var displayMessage: String {
        let message = info.lastAssistantMessage
        return message.count > 500
            ? String(message.suffix(500))
            : message
    }

    private func submitResponse() {
        guard !responseText.isEmpty else { return }
        onSubmit(responseText)
    }
}
