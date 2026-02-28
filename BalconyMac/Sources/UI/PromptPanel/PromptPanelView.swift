import SwiftUI
import BalconyShared

// MARK: - Panel Theme

/// Terracotta color palette matching the Battery companion app.
private enum PanelTheme {
    /// Primary brand — terracotta orange (#D97757)
    static let brand = Color(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0)
    /// Darker brand variant (#B85A3A)
    static let brandDark = Color(red: 0xB8/255.0, green: 0x5A/255.0, blue: 0x3A/255.0)
    /// Lighter brand variant (#F0C4AE)
    static let brandLight = Color(red: 0xF0/255.0, green: 0xC4/255.0, blue: 0xAE/255.0)
    /// Very light brand variant (#F5D9CB)
    static let brandLighter = Color(red: 0xF5/255.0, green: 0xD9/255.0, blue: 0xCB/255.0)

    /// Panel background tint — translucent warm tone layered over vibrancy blur
    static let backgroundTint = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0x19/255.0, green: 0x18/255.0, blue: 0x14/255.0, alpha: 0.3)
                : NSColor(red: 0xFA/255.0, green: 0xF8/255.0, blue: 0xF4/255.0, alpha: 0.5)
        }
    ))

    /// Surface for buttons and input fields
    static let surface = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.07)
                : NSColor(white: 0.0, alpha: 0.04)
        }
    ))

    /// Divider color
    static let divider = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.08)
                : NSColor(white: 0.0, alpha: 0.06)
        }
    ))

    /// Primary text
    static let textPrimary = Color.primary

    /// Secondary text
    static let textSecondary = Color.secondary

    /// Tertiary/muted text
    static let textTertiary = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.3)
                : NSColor(white: 0.0, alpha: 0.25)
        }
    ))
}

// MARK: - Vibrancy Background

/// Frosted glass blur layered behind the translucent theme tint.
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

/// Combined panel background: vibrancy blur + translucent warm tint.
private struct PanelBackground: View {
    var body: some View {
        VibrancyBackground()
            .overlay(PanelTheme.backgroundTint)
    }
}

// MARK: - Dismiss Button

/// Small X button for dismissing panels.
private struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(PanelTheme.textTertiary)
                .frame(width: 18, height: 18)
                .background(PanelTheme.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permission Prompt Panel

/// Notification-style view for permission requests.
struct PromptPanelView: View {
    let info: PermissionPromptInfo
    let onAction: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(PanelTheme.brand.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: toolIconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PanelTheme.brand)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(info.toolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelTheme.textPrimary)

                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(PanelTheme.textSecondary)
                    }
                }

                Spacer()

                riskBadge

                DismissButton(action: onDismiss)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            PanelTheme.divider
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Content preview
            if let content = contentPreview {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PanelTheme.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                PanelTheme.divider
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }

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
        .background(PanelBackground())
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
        case .elevated: return PanelTheme.brand
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
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(PanelTheme.brand.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PanelTheme.brand)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude is waiting")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelTheme.textPrimary)

                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(PanelTheme.textSecondary)
                    }
                }

                Spacer()

                DismissButton(action: onDismiss)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            PanelTheme.divider
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Claude's message
            Text(displayMessage)
                .font(.system(size: 12))
                .foregroundStyle(PanelTheme.textSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            PanelTheme.divider
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Text input row
            HStack(spacing: 8) {
                TextField("Type a response...", text: $responseText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.textPrimary)
                    .focused($textFieldFocused)
                    .onSubmit { submitResponse() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(PanelTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button(action: submitResponse) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(responseText.isEmpty ? PanelTheme.textTertiary : PanelTheme.brand)
                }
                .buttonStyle(.plain)
                .disabled(responseText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(PanelBackground())
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
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(PanelTheme.brand.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "questionmark.bubble")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PanelTheme.brand)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude has a question")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelTheme.textPrimary)

                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(PanelTheme.textSecondary)
                    }
                }

                Spacer()

                DismissButton(action: onDismiss)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            PanelTheme.divider
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Question text
            if let detected = info.detectedOptions {
                Text(detected.question)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                PanelTheme.divider
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }

            // Option buttons
            VStack(spacing: 4) {
                ForEach(options, id: \.index) { option in
                    if option.isOther {
                        if showOtherInput {
                            HStack(spacing: 8) {
                                TextField("Type your response...", text: $otherText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundStyle(PanelTheme.textPrimary)
                                    .focused($otherFieldFocused)
                                    .onSubmit { submitOther(option: option) }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(PanelTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Button(action: { submitOther(option: option) }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(otherText.isEmpty ? PanelTheme.textTertiary : PanelTheme.brand)
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
                                        .foregroundStyle(PanelTheme.textPrimary)
                                    Spacer()
                                    Image(systemName: "text.cursor")
                                        .font(.system(size: 10))
                                        .foregroundStyle(PanelTheme.textTertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(PanelTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: { onSelect(option) }) {
                            HStack {
                                Text(option.label)
                                    .font(.system(size: 12))
                                    .foregroundStyle(PanelTheme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(PanelTheme.textTertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(PanelTheme.surface)
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
        .background(PanelBackground())
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
        onSelect(option)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onTextSubmit(otherText)
        }
    }
}

// MARK: - Panel Button

/// Styled button using the terracotta theme.
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
        case .default: return PanelTheme.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .primary: return PanelTheme.brand
        case .destructive: return PanelTheme.surface
        case .default: return PanelTheme.surface
        }
    }
}
