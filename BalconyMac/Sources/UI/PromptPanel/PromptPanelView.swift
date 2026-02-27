import SwiftUI
import BalconyShared

// MARK: - Dark Panel Colors

private enum PanelColors {
    static let background = Color(white: 0.12)
    static let surface = Color(white: 0.16)
    static let contentBox = Color.white.opacity(0.05)
    static let ghostButton = Color.white.opacity(0.1)
    static let primaryButton = Color(red: 0.35, green: 0.38, blue: 0.95)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    static let fieldBackground = Color.white.opacity(0.08)
    static let dismissButton = Color.white.opacity(0.1)
}

// MARK: - Permission Prompt Panel

/// Notification-style view for permission requests.
struct PromptPanelView: View {
    let info: PermissionPromptInfo
    let onAction: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(riskColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: toolIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(riskColor)
            }
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Tool name
            Text(info.toolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PanelColors.textPrimary)

            // Project name + risk badge
            HStack(spacing: 6) {
                if let projectName {
                    Text(projectName)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelColors.textSecondary)
                        .lineLimit(1)
                }

                riskBadge
            }
            .padding(.top, 3)

            // Content preview
            if let content = contentPreview {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PanelColors.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PanelColors.contentBox)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: { onAction("n") }) {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelColors.textPrimary)
                .background(PanelColors.ghostButton)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: { onAction("a") }) {
                    Text("Always")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelColors.textPrimary)
                .background(PanelColors.ghostButton)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: { onAction("y") }) {
                    HStack(spacing: 4) {
                        Text("Allow")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .background(PanelColors.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 340)
        .background(PanelColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
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
            .background(riskColor.opacity(0.2))
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
        VStack(spacing: 0) {
            // Dismiss button (top-right)
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(PanelColors.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(PanelColors.dismissButton)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
            .padding(.top, 12)

            // Icon badge
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 10)

            // Title
            Text("Claude is waiting")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PanelColors.textPrimary)

            // Project name
            if let projectName {
                Text(projectName)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelColors.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }

            // Claude's message
            Text(displayMessage)
                .font(.system(size: 12))
                .foregroundStyle(PanelColors.textSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Text input row
            HStack(spacing: 8) {
                TextField("Type a response...", text: $responseText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelColors.textPrimary)
                    .focused($textFieldFocused)
                    .onSubmit { submitResponse() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(PanelColors.fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: submitResponse) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(responseText.isEmpty ? PanelColors.textTertiary : PanelColors.primaryButton)
                }
                .buttonStyle(.plain)
                .disabled(responseText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .frame(width: 340)
        .background(PanelColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
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
