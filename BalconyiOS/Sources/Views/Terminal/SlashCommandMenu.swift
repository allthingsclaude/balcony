import SwiftUI
import BalconyShared

/// Popup menu showing available Claude Code slash commands.
/// Filters as the user types after "/".
struct SlashCommandMenu: View {
    let commands: [SlashCommandInfo]
    let query: String
    let onSelect: (SlashCommandInfo) -> Void

    private var filteredCommands: [SlashCommandInfo] {
        let trimmed = query.lowercased()
        if trimmed.isEmpty { return commands }
        return commands.filter { cmd in
            cmd.name.lowercased().contains(trimmed) ||
            cmd.description.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        if filteredCommands.isEmpty {
            EmptyView()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCommands) { command in
                        Button {
                            BalconyTheme.hapticLight()
                            onSelect(command)
                        } label: {
                            commandRow(command)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 280)
            .background {
                RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
            }
            .clipShape(RoundedRectangle(cornerRadius: BalconyTheme.radiusMD))
        }
    }

    // MARK: - Row

    private func commandRow(_ command: SlashCommandInfo) -> some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            sourceIcon(command.source)
                .font(.system(size: 14))
                .foregroundStyle(BalconyTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(command.displayName)
                        .font(BalconyTheme.monoFont(14))
                        .foregroundStyle(BalconyTheme.textPrimary)

                    if let hint = command.argumentHint {
                        Text(hint)
                            .font(BalconyTheme.monoFont(10))
                            .foregroundStyle(BalconyTheme.textSecondary.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Text(command.description)
                    .font(BalconyTheme.bodyFont(12))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            sourceBadge(command.source)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Source Indicators

    private func sourceIcon(_ source: SlashCommandInfo.Source) -> Image {
        switch source {
        case .builtIn: return Image(systemName: "terminal")
        case .global: return Image(systemName: "globe")
        case .project: return Image(systemName: "folder")
        }
    }

    @ViewBuilder
    private func sourceBadge(_ source: SlashCommandInfo.Source) -> some View {
        switch source {
        case .builtIn:
            Text("claude")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BalconyTheme.textSecondary.opacity(0.1), in: Capsule())
        case .global:
            Text("global")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BalconyTheme.textPrimary.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BalconyTheme.textSecondary.opacity(0.2), in: Capsule())
        case .project:
            Text("project")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BalconyTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BalconyTheme.accentSubtle, in: Capsule())
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let sampleCommands: [SlashCommandInfo] = [
        .init(name: "help", description: "Get help with Claude Code", source: .builtIn),
        .init(name: "debug", description: "Investigate and diagnose issues", source: .global, argumentHint: "[error or file]"),
        .init(name: "test", description: "Run tests with analysis", source: .project),
    ]

    ZStack {
        BalconyTheme.background.ignoresSafeArea()

        VStack {
            Spacer()
            SlashCommandMenu(commands: sampleCommands, query: "") { cmd in
                print("Selected: \(cmd.displayName)")
            }
            .padding(.horizontal, 16)
        }
    }
}
#endif
