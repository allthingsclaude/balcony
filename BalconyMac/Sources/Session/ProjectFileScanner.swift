import Foundation
import os

/// Scans a project directory to produce a flat list of relative file paths
/// for the iOS @ file picker.
enum ProjectFileScanner {
    private static let logger = Logger(subsystem: "com.balcony.mac", category: "ProjectFileScanner")

    /// Directories to always skip.
    private static let skipDirs: Set<String> = [
        ".git", "node_modules", ".build", ".swiftpm", "DerivedData",
        "Pods", "Carthage", ".next", "dist", "build", "__pycache__",
        ".cache", ".turbo", "coverage", ".nyc_output", "vendor",
        ".gradle", ".idea", ".vscode",
    ]

    /// Extensions to skip (binary / large assets).
    private static let skipExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "ico", "webp", "bmp", "tiff",
        "mp3", "mp4", "wav", "mov", "avi",
        "zip", "tar", "gz", "rar", "7z",
        "pdf", "exe", "dll", "dylib", "so", "a", "o",
        "woff", "woff2", "ttf", "eot",
        "lock",
    ]

    private static let maxFiles = 3000

    /// Scan the project at `path` and return relative file paths.
    static func scan(projectPath: String) -> [String] {
        let url = URL(fileURLWithPath: projectPath)
        let fm = FileManager.default
        var files: [String] = []

        let gitignorePatterns = loadGitignore(at: url)

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Could not enumerate \(projectPath)")
            return []
        }

        while let item = enumerator.nextObject() as? URL {
            let name = item.lastPathComponent

            // Skip directories.
            if let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true {
                if skipDirs.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Skip binary extensions.
            let ext = item.pathExtension.lowercased()
            if skipExtensions.contains(ext) { continue }

            // Relative path.
            let relative = item.path.replacingOccurrences(of: projectPath + "/", with: "")

            // Skip gitignore matches.
            if matchesGitignore(relative, patterns: gitignorePatterns) { continue }

            files.append(relative)
            if files.count >= maxFiles { break }
        }

        files.sort()
        logger.info("Scanned \(files.count) files in \(projectPath)")
        return files
    }

    // MARK: - Gitignore

    private static func loadGitignore(at projectURL: URL) -> [String] {
        let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) else { return [] }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func matchesGitignore(_ path: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            let cleaned = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.contains(cleaned) { return true }
        }
        return false
    }
}
