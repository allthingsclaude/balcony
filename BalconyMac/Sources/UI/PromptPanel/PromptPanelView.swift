import SwiftUI
import BalconyShared

// MARK: - Permission Prompt Panel

/// Notification-style view for permission requests.
struct PromptPanelView: View {
    let info: PermissionPromptInfo
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: toolIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(riskColor)

                Text(info.toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let projectName {
                    Text(projectName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                riskBadge
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Content preview
            if let content = contentPreview {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            // Action buttons
            HStack(spacing: 6) {
                Spacer()

                Button("Deny") { onAction("n") }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Button("Always") { onAction("a") }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Button("Allow") { onAction("y") }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    // MARK: - Computed

    private var contentPreview: String? {
        if let command = info.command, !command.isEmpty {
            return String(command.prefix(200))
        }
        if let filePath = info.filePath, !filePath.isEmpty {
            return abbreviatePath(filePath)
        }
        if let detail = info.detail, !detail.isEmpty {
            return String(detail.prefix(200))
        }
        return nil
    }

    private var projectName: String? {
        guard let cwd = info.cwd else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private var riskBadge: some View {
        Text(riskLabel)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(riskColor.opacity(0.12))
            .foregroundStyle(riskColor)
            .clipShape(Capsule())
    }

    private func abbreviatePath(_ path: String) -> String {
        if let cwd = info.cwd, path.hasPrefix(cwd) {
            let relative = String(path.dropFirst(cwd.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private var toolIconName: String {
        switch info.toolName {
        case "Bash": return "terminal"
        case "Edit": return "pencil.line"
        case "Write": return "doc.badge.plus"
        case "Read": return "doc.text.magnifyingglass"
        case "Glob": return "folder.badge.questionmark"
        case "Grep": return "magnifyingglass"
        case "Task": return "arrow.triangle.branch"
        case "WebFetch": return "globe"
        case "WebSearch": return "magnifyingglass.circle"
        case "NotebookEdit": return "book"
        default: return "gearshape"
        }
    }

    private var riskColor: Color {
        switch info.riskLevel {
        case .normal: return .green
        case .elevated: return .orange
        case .destructive: return .red
        }
    }

    private var riskLabel: String {
        switch info.riskLevel {
        case .normal: return "Low"
        case .elevated: return "Elevated"
        case .destructive: return "Destructive"
        }
    }
}

// MARK: - Idle Prompt Panel

/// Notification-style view for idle prompts (Claude waiting for input).
struct IdlePromptPanelView: View {
    let info: IdlePromptInfo
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var responseText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Claude is waiting")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let projectName {
                    Text(projectName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Claude's message
            Text(displayMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            // Text input row
            HStack(spacing: 6) {
                TextField("Type a response...", text: $responseText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($textFieldFocused)
                    .onSubmit { submitResponse() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button(action: submitResponse) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(responseText.isEmpty ? Color.secondary.opacity(0.3) : .blue)
                }
                .buttonStyle(.plain)
                .disabled(responseText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .onAppear { textFieldFocused = true }
    }

    private var projectName: String? {
        guard let cwd = info.cwd else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private var displayMessage: String {
        let message = info.lastAssistantMessage
        return message.count > 500 ? String(message.suffix(500)) : message
    }

    private func submitResponse() {
        guard !responseText.isEmpty else { return }
        onSubmit(responseText)
    }
}
