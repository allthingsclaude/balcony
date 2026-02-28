import SwiftUI
import BalconyShared

// MARK: - Vibrancy Background

/// Frosted glass background matching native macOS notifications.
/// Uses NSVisualEffectView with `.popover` material for the system blur.
private struct VibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Permission Prompt Panel

/// Notification-style view for permission requests, styled like native macOS notifications.
struct PromptPanelView: View {
    let info: PermissionPromptInfo
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: app icon + title + subtitle
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Balcony")
                        .font(.system(size: 13, weight: .semibold))

                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                riskBadge
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            // Tool name + content
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(info.toolName)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: toolIconName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let content = contentPreview {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 14)

            // Action buttons
            HStack(spacing: 6) {
                PanelButton("Deny", role: .destructive) { onAction("n") }
                PanelButton("Always") { onAction("a") }
                PanelButton("Allow", role: .primary) { onAction("y") }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(VibrancyBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor.opacity(0.15))
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

/// Notification-style view for idle prompts (Claude waiting for input),
/// styled like native macOS notifications.
struct IdlePromptPanelView: View {
    let info: IdlePromptInfo
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var responseText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: app icon + title + dismiss
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude is waiting")
                        .font(.system(size: 13, weight: .semibold))

                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(.quaternary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            // Claude's message
            Text(displayMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 14)

            // Text input row
            HStack(spacing: 8) {
                TextField("Type a response...", text: $responseText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($textFieldFocused)
                    .onSubmit { submitResponse() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button(action: submitResponse) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(responseText.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(responseText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(VibrancyBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
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

// MARK: - Multi-Option Panel

/// Notification-style view for AskUserQuestion prompts with selectable options.
struct MultiOptionPanelView: View {
    let info: IdlePromptInfo
    let options: [ParsedOption]
    let onSelect: (ParsedOption) -> Void
    let onTextSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var otherText = ""
    @State private var showOtherInput = false
    @FocusState private var otherFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: app icon + title + dismiss
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude has a question")
                        .font(.system(size: 13, weight: .semibold))

                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(.quaternary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            // Question text
            if let detected = info.detectedOptions {
                Text(detected.question)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 14)
            }

            // Option buttons
            VStack(spacing: 4) {
                ForEach(options, id: \.index) { option in
                    if option.isOther {
                        // "Other" button toggles text input
                        if showOtherInput {
                            HStack(spacing: 8) {
                                TextField("Type your response...", text: $otherText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .focused($otherFieldFocused)
                                    .onSubmit { submitOther(option: option) }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Button(action: { submitOther(option: option) }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(otherText.isEmpty ? Color.secondary : Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(otherText.isEmpty)
                            }
                        } else {
                            Button(action: {
                                showOtherInput = true
                                otherFieldFocused = true
                            }) {
                                HStack {
                                    Text(option.label)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Image(systemName: "text.cursor")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: { onSelect(option) }) {
                            HStack {
                                Text(option.label)
                                    .font(.system(size: 12))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(VibrancyBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private var projectName: String? {
        guard let cwd = info.cwd else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private func submitOther(option: ParsedOption) {
        guard !otherText.isEmpty else { return }
        // Select "Other" option first (navigate to it), then send the text
        onSelect(option)
        // Small delay to let the option selection register, then type text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onTextSubmit(otherText)
        }
    }
}

// MARK: - Panel Button

/// Styled button matching macOS notification action buttons.
private struct PanelButton: View {
    let title: String
    let role: ButtonRole
    let action: () -> Void

    init(_ title: String, role: ButtonRole = .default, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    enum ButtonRole {
        case `default`
        case primary
        case destructive
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: role == .primary ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var foregroundColor: Color {
        switch role {
        case .primary: return .white
        case .destructive: return .red
        case .default: return .primary
        }
    }

    private var backgroundColor: some ShapeStyle {
        switch role {
        case .primary: return AnyShapeStyle(Color.accentColor)
        case .destructive: return AnyShapeStyle(.quaternary)
        case .default: return AnyShapeStyle(.quaternary)
        }
    }
}
