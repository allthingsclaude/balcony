import Foundation
import BalconyShared
import os

/// Scans the filesystem for Claude Code slash commands.
///
/// Discovers commands from three sources:
/// 1. Built-in commands (hardcoded list of Claude Code defaults)
/// 2. Global user commands: `~/.claude/commands/*.md`
/// 3. Project-level commands: `<projectPath>/.claude/commands/*.md`
enum SlashCommandScanner {
    private static let logger = Logger(subsystem: "com.balcony.mac", category: "SlashCommandScanner")

    /// Scan all sources and return a merged, deduplicated list of commands.
    /// Project commands override global, global override built-in.
    static func scan(projectPath: String) -> [SlashCommandInfo] {
        let builtIn = builtInCommands
        let global = scanDirectory(
            path: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/commands").path,
            source: .global
        )
        let project = scanDirectory(
            path: (projectPath as NSString).appendingPathComponent(".claude/commands"),
            source: .project
        )

        // Merge: project > global > builtIn (by name)
        var byName: [String: SlashCommandInfo] = [:]
        for cmd in builtIn { byName[cmd.name] = cmd }
        for cmd in global { byName[cmd.name] = cmd }
        for cmd in project { byName[cmd.name] = cmd }

        // Sort: project first, then global, then built-in; alphabetical within each group.
        return byName.values.sorted { a, b in
            let aPriority = a.source.sortPriority
            let bPriority = b.source.sortPriority
            if aPriority != bPriority { return aPriority < bPriority }
            return a.name < b.name
        }
    }

    // MARK: - Directory Scanner

    private static func scanDirectory(path: String, source: SlashCommandInfo.Source) -> [SlashCommandInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [] }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var commands: [SlashCommandInfo] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }

            // Build command name from relative path: "frontend/lint.md" → "frontend:lint"
            let relativePath = url.path.replacingOccurrences(of: path + "/", with: "")
            let name = relativePath
                .replacingOccurrences(of: ".md", with: "")
                .replacingOccurrences(of: "/", with: ":")

            if let cmd = parseCommandFile(at: url, name: name, source: source) {
                commands.append(cmd)
            }
        }
        return commands
    }

    // MARK: - Frontmatter Parser

    private static func parseCommandFile(
        at url: URL,
        name: String,
        source: SlashCommandInfo.Source
    ) -> SlashCommandInfo? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            logger.warning("Could not read command file: \(url.path)")
            return nil
        }

        var description = name
        var argumentHint: String?

        // Parse YAML frontmatter between --- delimiters
        if content.hasPrefix("---") {
            let lines = content.components(separatedBy: .newlines)
            for line in lines.dropFirst() {
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }

                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)

                switch key {
                case "description":
                    description = value
                case "argument-hint":
                    argumentHint = value
                default:
                    break
                }
            }
        }

        return SlashCommandInfo(
            name: name,
            description: description,
            source: source,
            argumentHint: argumentHint
        )
    }

    // MARK: - Built-in Commands

    private static let builtInCommands: [SlashCommandInfo] = [
        .init(name: "help", description: "Get help with Claude Code", source: .builtIn),
        .init(name: "clear", description: "Clear conversation history", source: .builtIn),
        .init(name: "compact", description: "Compact conversation with optional instructions", source: .builtIn, argumentHint: "[instructions]"),
        .init(name: "config", description: "Open configuration", source: .builtIn),
        .init(name: "cost", description: "Show token usage and cost", source: .builtIn),
        .init(name: "doctor", description: "Check installation health", source: .builtIn),
        .init(name: "init", description: "Initialize project with CLAUDE.md", source: .builtIn),
        .init(name: "login", description: "Switch account or log in", source: .builtIn),
        .init(name: "logout", description: "Sign out of your account", source: .builtIn),
        .init(name: "memory", description: "Edit Claude's memory files", source: .builtIn),
        .init(name: "model", description: "Switch AI model", source: .builtIn, argumentHint: "[model name]"),
        .init(name: "permissions", description: "View and manage permissions", source: .builtIn),
        .init(name: "review", description: "Review code changes", source: .builtIn),
        .init(name: "status", description: "Show session status", source: .builtIn),
        .init(name: "terminal-setup", description: "Setup terminal theme", source: .builtIn),
        .init(name: "vim", description: "Toggle vim keybindings", source: .builtIn),
        .init(name: "bug", description: "Report a bug", source: .builtIn),
        .init(name: "mcp", description: "View MCP server status", source: .builtIn),
        .init(name: "resume", description: "Resume a previous conversation", source: .builtIn, argumentHint: "[session id or name]"),
        .init(name: "context", description: "Visualize context window usage", source: .builtIn),
        .init(name: "theme", description: "Change color theme", source: .builtIn),
        .init(name: "todos", description: "List TODO items", source: .builtIn),
        .init(name: "hooks", description: "Manage hooks", source: .builtIn),
        .init(name: "export", description: "Export conversation", source: .builtIn),
    ]
}
