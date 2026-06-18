import Foundation

/// Derives the directory name Claude Code uses for a project's session files under
/// `~/.claude/projects/`.
///
/// Claude Code collapses the project path's `/`, `.` and `_` characters to `-`. (An earlier
/// implementation replaced only `/`, so a project under a path containing `.` or `_`
/// resolved to a directory that does not exist.)
public enum ClaudeProjectHash {
    /// The hashed directory name for a project path (e.g. `/Users/x/my_app` → `-Users-x-my-app`).
    public static func hash(_ projectPath: String) -> String {
        projectPath.replacingOccurrences(of: "[/._]", with: "-", options: .regularExpression)
    }

    /// The legacy hash (only `/` replaced), kept for back-compat resolution of directories
    /// created before the `.`/`_` collapse was corrected.
    public static func legacyHash(_ projectPath: String) -> String {
        projectPath.replacingOccurrences(of: "/", with: "-")
    }
}
