import Foundation
import BalconyShared
import os

/// Provides the hardcoded model catalog and detects the current model from session JSONL files.
actor ModelListProvider {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "ModelListProvider")

    /// All known Claude Code models.
    /// Using short names (opus, sonnet, haiku) so Claude Code resolves to the latest version.
    let models: [ModelInfo] = [
        ModelInfo(
            id: "opus",
            displayName: "Opus",
            description: "Most capable — deep reasoning and complex tasks",
            tier: .opus
        ),
        ModelInfo(
            id: "sonnet",
            displayName: "Sonnet",
            description: "Balanced speed and intelligence",
            tier: .sonnet
        ),
        ModelInfo(
            id: "haiku",
            displayName: "Haiku",
            description: "Fast and lightweight for quick tasks",
            tier: .haiku
        ),
    ]

    /// Detect the current model from the most recent assistant message in JSONL session files.
    ///
    /// Scans `~/.claude/projects/{projectHash}/` for the most recently modified `.jsonl` file
    /// (skipping `agent-` prefixed subagent files), then reads the tail looking for a `"model"` field.
    func currentModelForProject(_ projectPath: String) -> String? {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            logger.debug("No .claude/projects directory found")
            return nil
        }

        // Find the project hash directory that matches this project path.
        // Claude Code hashes the project path — we find the dir by looking at session files.
        var bestFile: URL?
        var bestDate = Date.distantPast

        for dir in projectDirs {
            let jsonlFiles = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ))?.filter { url in
                url.pathExtension == "jsonl" && !url.lastPathComponent.hasPrefix("agent-")
            } ?? []

            for file in jsonlFiles {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                if modDate > bestDate {
                    bestDate = modDate
                    bestFile = file
                }
            }
        }

        guard let file = bestFile else {
            logger.debug("No JSONL session files found")
            return nil
        }

        return extractModelFromTail(of: file)
    }

    /// Read the last 32KB of a JSONL file and scan lines in reverse for a "model" field
    /// in assistant messages.
    private func extractModelFromTail(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let tailSize: UInt64 = 32 * 1024
        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > tailSize ? fileSize - tailSize : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.components(separatedBy: .newlines).reversed()
        for line in lines {
            guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else {
                continue
            }
            guard line.contains("\"model\"") else { continue }

            // Quick extraction: find "model":"<value>" pattern
            if let model = extractJSONValue(key: "model", from: line) {
                logger.info("Detected current model: \(model)")
                return model
            }
        }

        return nil
    }

    /// Extract a string value for a given key from a JSON line without full parsing.
    private func extractJSONValue(key: String, from line: String) -> String? {
        // Match both "key":"value" and "key": "value"
        let patterns = ["\"\(key)\":\"", "\"\(key)\": \""]
        for pattern in patterns {
            guard let range = line.range(of: pattern) else { continue }
            let start = range.upperBound
            guard let end = line[start...].firstIndex(of: "\"") else { continue }
            return String(line[start..<end])
        }
        return nil
    }
}
