import Foundation
import BalconyShared
import os

/// Reads Claude Code session files from `~/.claude/projects/` and extracts metadata.
actor SessionFileReader {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "SessionFileReader")

    /// List all available sessions for a given project path.
    /// Sessions are sorted by last modified date (newest first).
    func listSessions(for projectPath: String) async -> [SessionInfo] {
        let projectHash = hashProjectPath(projectPath)
        let sessionsDir = claudeProjectsPath().appendingPathComponent(projectHash)

        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            logger.debug("No sessions directory for project: \(projectPath)")
            return []
        }

        var sessions: [SessionInfo] = []

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: sessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            for fileURL in files where fileURL.pathExtension == "jsonl" {
                if let sessionInfo = await parseSessionFile(fileURL, projectPath: projectPath) {
                    sessions.append(sessionInfo)
                }
            }
        } catch {
            logger.error("Failed to read sessions directory: \(error.localizedDescription)")
            return []
        }

        // Sort by last modified (newest first)
        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Session File Parsing

    /// Parse a session JSONL file to extract metadata.
    private func parseSessionFile(_ fileURL: URL, projectPath: String) async -> SessionInfo? {
        let sessionId = fileURL.deletingPathExtension().lastPathComponent

        // Get file attributes
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modDate = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        // Extract title and branch from session content
        let (title, branch) = await extractSessionMetadata(from: fileURL)

        return SessionInfo(
            id: sessionId,
            projectPath: projectPath,
            title: title ?? sessionId, // Fall back to session ID if no title found
            lastModified: modDate,
            fileSize: fileSize,
            branch: branch
        )
    }

    /// Extract title and branch from the first few lines of a session JSONL file.
    private func extractSessionMetadata(from fileURL: URL) async -> (title: String?, branch: String?) {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return (nil, nil)
        }

        defer { try? fileHandle.close() }

        var title: String?
        var branch: String?
        var linesRead = 0
        let maxLines = 50 // Only read first 50 lines for performance

        while linesRead < maxLines {
            guard let lineData = try? fileHandle.readLine() else { break }
            linesRead += 1

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Extract title from first user message
            if title == nil, let type = json["type"] as? String, type == "user" {
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] {
                    if let text = content as? String {
                        title = extractTitleFromText(text)
                    } else if let blocks = content as? [[String: Any]],
                              let firstBlock = blocks.first,
                              let blockType = firstBlock["type"] as? String,
                              blockType == "text",
                              let text = firstBlock["text"] as? String {
                        title = extractTitleFromText(text)
                    }
                }
            }

            // Extract branch from JSONL (Claude Code writes gitBranch at top level)
            if branch == nil, let b = json["gitBranch"] as? String, !b.isEmpty {
                branch = b
            }

            // Stop once we have both
            if title != nil && branch != nil {
                break
            }
        }

        return (title, branch)
    }

    /// Extract a clean title from user message text (first line, max 60 chars).
    private func extractTitleFromText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Take first line only
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed

        // Limit to 60 characters
        if firstLine.count > 60 {
            let index = firstLine.index(firstLine.startIndex, offsetBy: 60)
            return String(firstLine[..<index]) + "..."
        }

        return firstLine
    }

    // MARK: - Path Helpers

    /// Get the path to `~/.claude/projects/`.
    private func claudeProjectsPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    /// Convert a project path to Claude Code's directory naming convention.
    /// Claude Code replaces "/" with "-" in the absolute path.
    /// e.g. "/Users/alice/repos/myproject" → "-Users-alice-repos-myproject"
    private func hashProjectPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
    }
}

// MARK: - FileHandle Extension

extension FileHandle {
    /// Read a single line from the file handle.
    fileprivate func readLine() throws -> Data? {
        var lineData = Data()

        while true {
            let byte = try read(upToCount: 1)

            if byte == nil || byte?.isEmpty == true {
                return lineData.isEmpty ? nil : lineData
            }

            if byte?[0] == UInt8(ascii: "\n") {
                return lineData
            }

            if let byte = byte {
                lineData.append(byte)
            }
        }
    }
}
