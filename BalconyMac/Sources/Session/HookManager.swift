import Foundation
import os

/// Manages Claude Code hooks for BalconyMac integration.
actor HookManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookManager")
    private let hooksDir: String

    init(hooksDir: String = "\(NSHomeDirectory())/.claude/hooks") {
        self.hooksDir = hooksDir
    }

    /// Install Balcony hooks into Claude Code hooks directory.
    func installHooks() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        let hooks = ["PreToolUse", "PostToolUse", "Notification", "Stop"]
        for hookName in hooks {
            let hookPath = "\(hooksDir)/\(hookName).sh"
            if !fm.fileExists(atPath: hookPath) {
                let script = generateHookScript(name: hookName)
                try script.write(toFile: hookPath, atomically: true, encoding: .utf8)
                // Make executable
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
                logger.info("Installed hook: \(hookName)")
            }
        }
    }

    /// Remove Balcony hooks.
    func removeHooks() throws {
        let fm = FileManager.default
        let hooks = ["PreToolUse", "PostToolUse", "Notification", "Stop"]
        for hookName in hooks {
            let hookPath = "\(hooksDir)/\(hookName).sh"
            if fm.fileExists(atPath: hookPath) {
                try fm.removeItem(atPath: hookPath)
                logger.info("Removed hook: \(hookName)")
            }
        }
    }

    private func generateHookScript(name: String) -> String {
        """
        #!/bin/bash
        # Balcony Claude Code Hook: \(name)
        # This hook forwards events to the BalconyMac agent.
        # Auto-generated - do not edit manually.

        SOCKET="/tmp/balcony.sock"
        if [ -S "$SOCKET" ]; then
            echo "{\\"hook\\": \\"\(name)\\", \\"data\\": $(cat -)}" | nc -U "$SOCKET" 2>/dev/null || true
        fi
        """
    }
}
