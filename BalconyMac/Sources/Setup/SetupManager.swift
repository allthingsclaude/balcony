import Foundation
import os

/// Manages first-launch setup: installs hook-handler, CLI binary, patches Claude Code hooks,
/// and optionally adds a shell alias.
@MainActor
final class SetupManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "Setup")

    // MARK: - Constants

    static let setupCompleteKey = "setupComplete"

    private let balconyDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".balcony")
    private let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    private let usrLocalBin = URL(fileURLWithPath: "/usr/local/bin")

    // MARK: - State Detection

    /// Whether first-launch setup has been completed.
    var isSetupComplete: Bool {
        UserDefaults.standard.bool(forKey: Self.setupCompleteKey)
    }

    /// Mark setup as complete.
    func markComplete() {
        UserDefaults.standard.set(true, forKey: Self.setupCompleteKey)
        logger.info("Setup marked as complete")
    }

    /// Reset setup flag so the wizard runs again.
    func resetSetup() {
        UserDefaults.standard.removeObject(forKey: Self.setupCompleteKey)
        logger.info("Setup flag reset")
    }

    // MARK: - State Checks

    /// Check if ~/.balcony/ directory exists.
    var isBalconyDirPresent: Bool {
        FileManager.default.fileExists(atPath: balconyDir.path)
    }

    /// Check if ~/.balcony/hook-handler exists and is executable.
    var isHookHandlerInstalled: Bool {
        let path = balconyDir.appendingPathComponent("hook-handler").path
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Check if /usr/local/bin/balcony exists.
    var isCLIInstalled: Bool {
        FileManager.default.fileExists(atPath: usrLocalBin.appendingPathComponent("balcony").path)
    }

    /// Check if Claude Code settings.json contains Balcony hooks.
    var areHooksPatched: Bool {
        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        // Check if at least the PreToolUse hook references hook-handler
        if let preToolUse = hooks["PreToolUse"] as? [[String: Any]] {
            return preToolUse.contains { entry in
                (entry["command"] as? String)?.contains("hook-handler") == true
            }
        }
        return false
    }

    /// Check if the balcony alias exists in the user's shell profile.
    var isAliasInstalled: Bool {
        guard let profilePath = shellProfilePath else { return false }
        guard let contents = try? String(contentsOfFile: profilePath, encoding: .utf8) else { return false }
        return contents.contains("alias claude=balcony") || contents.contains("alias claude='balcony'")
    }

    // MARK: - Step 1: Create ~/.balcony/

    /// Create the ~/.balcony/ directory.
    func createBalconyDir() throws {
        try FileManager.default.createDirectory(at: balconyDir, withIntermediateDirectories: true)
        logger.info("Created ~/.balcony/")
    }

    // MARK: - Step 2: Install hook-handler

    /// Copy hook-handler from app bundle to ~/.balcony/hook-handler.
    func installHookHandler() throws {
        guard let bundledPath = Bundle.main.path(forResource: "hook-handler", ofType: nil) else {
            throw SetupError.resourceNotFound("hook-handler")
        }

        let destPath = balconyDir.appendingPathComponent("hook-handler")

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }

        try FileManager.default.copyItem(atPath: bundledPath, toPath: destPath.path)

        // chmod +x
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destPath.path
        )
        logger.info("Installed hook-handler to ~/.balcony/")
    }

    // MARK: - Step 3: Install CLI

    enum CLIInstallResult {
        case success
        case needsAdmin
        case failed(Error)
    }

    /// Attempt to copy the CLI binary to /usr/local/bin/balcony.
    /// Tries unprivileged first, falls back to returning `.needsAdmin`.
    func installCLI() -> CLIInstallResult {
        guard let bundledPath = Bundle.main.path(forResource: "balcony-cli", ofType: nil) else {
            return .failed(SetupError.resourceNotFound("balcony-cli"))
        }

        let destPath = usrLocalBin.appendingPathComponent("balcony").path

        // Ensure /usr/local/bin exists
        if !FileManager.default.fileExists(atPath: usrLocalBin.path) {
            do {
                try FileManager.default.createDirectory(at: usrLocalBin, withIntermediateDirectories: true)
            } catch {
                return .needsAdmin
            }
        }

        // Try direct copy
        do {
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(atPath: destPath)
            }
            try FileManager.default.copyItem(atPath: bundledPath, toPath: destPath)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
            logger.info("Installed CLI to /usr/local/bin/balcony")
            return .success
        } catch {
            logger.info("Unprivileged CLI install failed, needs admin: \(error.localizedDescription)")
            return .needsAdmin
        }
    }

    /// Install CLI with administrator privileges using AppleScript.
    func installCLIWithAdmin() throws {
        guard let bundledPath = Bundle.main.path(forResource: "balcony-cli", ofType: nil) else {
            throw SetupError.resourceNotFound("balcony-cli")
        }

        let destPath = usrLocalBin.appendingPathComponent("balcony").path

        let script = """
        do shell script "mkdir -p /usr/local/bin && cp '\(bundledPath)' '\(destPath)' && chmod +x '\(destPath)'" with administrator privileges
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw SetupError.adminInstallFailed("Failed to create AppleScript")
        }

        appleScript.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw SetupError.adminInstallFailed(message)
        }

        logger.info("Installed CLI to /usr/local/bin/balcony with admin privileges")
    }

    // MARK: - Step 4: Patch Claude Code settings.json

    /// Merge Balcony hooks into ~/.claude/settings.json without clobbering other settings.
    func patchHooks() throws {
        let settingsPath = claudeDir.appendingPathComponent("settings.json")

        // Ensure ~/.claude/ exists
        if !FileManager.default.fileExists(atPath: claudeDir.path) {
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        // Read existing settings or start fresh
        var settings: [String: Any]
        if let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        } else {
            settings = [:]
        }

        // Get or create hooks dict
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookCommand = "~/.balcony/hook-handler"

        let balconyHookEntry: [String: Any] = [
            "type": "command",
            "command": hookCommand
        ]

        // Hook event names to patch
        let hookNames = ["Notification", "PreToolUse", "Stop"]

        for hookName in hookNames {
            var entries = hooks[hookName] as? [[String: Any]] ?? []

            // Skip if already present
            let alreadyPresent = entries.contains { entry in
                (entry["command"] as? String)?.contains("hook-handler") == true
            }
            if !alreadyPresent {
                entries.append(balconyHookEntry)
            }
            hooks[hookName] = entries
        }

        settings["hooks"] = hooks

        // Write back
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsPath)

        logger.info("Patched Claude Code settings.json with Balcony hooks")
    }

    // MARK: - Step 5: Shell Alias

    /// The user's shell profile path based on $SHELL.
    var shellProfilePath: String? {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if shell.hasSuffix("zsh") {
            return "\(home)/.zshrc"
        } else if shell.hasSuffix("bash") {
            // Prefer .bash_profile on macOS
            let bashProfile = "\(home)/.bash_profile"
            let bashrc = "\(home)/.bashrc"
            if FileManager.default.fileExists(atPath: bashProfile) {
                return bashProfile
            }
            return bashrc
        } else if shell.hasSuffix("fish") {
            return "\(home)/.config/fish/config.fish"
        }
        return nil
    }

    /// The short name of the user's shell (e.g. "zsh", "bash", "fish").
    var shellName: String {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return "shell" }
        return URL(fileURLWithPath: shell).lastPathComponent
    }

    /// Add `alias claude=balcony` to the user's shell profile.
    func installAlias() throws {
        guard let profilePath = shellProfilePath else {
            throw SetupError.shellNotSupported
        }

        let guardComment = "# Added by Balcony"
        let aliasLine: String
        if shellName == "fish" {
            aliasLine = "alias claude balcony"
        } else {
            aliasLine = "alias claude=balcony"
        }

        // Read existing contents
        var contents = (try? String(contentsOfFile: profilePath, encoding: .utf8)) ?? ""

        // Check for duplicate
        if contents.contains(aliasLine) {
            logger.info("Alias already present in \(profilePath)")
            return
        }

        // Append with guard comment
        if !contents.hasSuffix("\n") && !contents.isEmpty {
            contents += "\n"
        }
        contents += "\n\(guardComment)\n\(aliasLine)\n"

        try contents.write(toFile: profilePath, atomically: true, encoding: .utf8)

        logger.info("Added alias to \(profilePath)")
    }
}

// MARK: - Errors

enum SetupError: LocalizedError {
    case resourceNotFound(String)
    case adminInstallFailed(String)
    case shellNotSupported

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Could not find \(name) in app bundle"
        case .adminInstallFailed(let message):
            return "Admin install failed: \(message)"
        case .shellNotSupported:
            return "Shell not supported for alias installation"
        }
    }
}
