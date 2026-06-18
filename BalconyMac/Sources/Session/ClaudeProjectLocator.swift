import Foundation
import BalconyShared

/// Resolves Claude Code's per-project session directory under `~/.claude/projects/`.
///
/// Centralizes the project-path → directory mapping that was previously duplicated (and
/// subtly wrong) across `SessionFileReader`, `ModelListProvider`, and `ConnectionManager`.
enum ClaudeProjectLocator {
    /// Root directory where Claude Code stores per-project session JSONL files.
    static func projectsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    /// Resolve the session directory for a project path.
    ///
    /// Prefers the correct collapsed hash (`/`, `.`, `_` → `-`). If that directory does not
    /// exist, falls back to the legacy `/`-only hash so installs created before the fix keep
    /// resolving. When neither exists yet, returns the correct-hash path.
    static func sessionDirectory(for projectPath: String) -> URL {
        let root = projectsRoot()
        let primary = root.appendingPathComponent(ClaudeProjectHash.hash(projectPath))
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        let legacy = root.appendingPathComponent(ClaudeProjectHash.legacyHash(projectPath))
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return primary
    }
}
