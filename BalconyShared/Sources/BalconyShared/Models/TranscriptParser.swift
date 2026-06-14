import Foundation

/// Parses Claude Code session JSONL into structured ``TranscriptEvent`` values.
///
/// This is the structured alternative to scraping the reconstructed PTY screen:
/// every turn is an explicit record, so there is no color/wrap/code-block
/// guessing. Each line of the transcript file is one JSON object; only `user`
/// and `assistant` records become events. Metadata records (`mode`, `ai-title`,
/// `permission-mode`, `attachment`, `file-history-snapshot`, `system`) are
/// skipped.
///
/// The parser uses `JSONSerialization` rather than `Codable` because the records
/// mix conventions: envelope fields are camelCase (`uuid`, `parentUuid`,
/// `isSidechain`) while message content blocks use the Anthropic API's
/// snake_case (`tool_use`, `tool_result`, `tool_use_id`, `is_error`), and
/// `message.content` is sometimes a string and sometimes an array.
public enum TranscriptParser {

    /// Tool-result bodies can be enormous (full file reads, command output).
    /// Cap what rides the wire — the transcript view collapses them anyway.
    public static let maxToolResultChars = 2000

    /// Parse a whole transcript blob (newline-delimited JSON).
    public static func parse(_ text: String) -> [TranscriptEvent] {
        var events: [TranscriptEvent] = []
        text.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let event = parseLine(data) else { return }
            events.append(event)
        }
        return events
    }

    /// Parse a single JSONL line. Returns nil for non-message records, malformed
    /// JSON, or messages with no renderable content.
    public static func parseLine(_ data: Data) -> TranscriptEvent? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parseObject(obj)
    }

    /// Parse an already-deserialized JSONL record.
    public static func parseObject(_ obj: [String: Any]) -> TranscriptEvent? {
        guard let typeString = obj["type"] as? String,
              let role = TranscriptEvent.Role(rawValue: typeString),
              let uuid = obj["uuid"] as? String,
              let message = obj["message"] as? [String: Any]
        else { return nil }

        let blocks = parseContent(message["content"], role: role)
        guard !blocks.isEmpty else { return nil }

        return TranscriptEvent(
            id: uuid,
            role: role,
            blocks: blocks,
            timestamp: parseTimestamp(obj["timestamp"]),
            isSidechain: obj["isSidechain"] as? Bool ?? false
        )
    }

    // MARK: - Content

    /// Normalize `message.content` (a string or an array of blocks) into blocks.
    private static func parseContent(_ content: Any?, role: TranscriptEvent.Role) -> [TranscriptBlock] {
        if let text = content as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [.text(trimmed)]
        }
        guard let array = content as? [[String: Any]] else { return [] }

        var blocks: [TranscriptBlock] = []
        for block in array {
            guard let kind = block["type"] as? String else { continue }
            switch kind {
            case "text":
                if let t = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !t.isEmpty {
                    blocks.append(.text(t))
                }
            case "thinking":
                if let t = (block["thinking"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !t.isEmpty {
                    blocks.append(.thinking(t))
                }
            case "tool_use":
                let id = block["id"] as? String ?? ""
                let name = block["name"] as? String ?? "tool"
                blocks.append(.toolUse(id: id, name: name, input: summarizeToolInput(name: name, input: block["input"])))
            case "tool_result":
                let id = block["tool_use_id"] as? String ?? ""
                let isError = block["is_error"] as? Bool ?? false
                blocks.append(.toolResult(toolUseID: id, text: flattenResult(block["content"]), isError: isError))
            case "image":
                blocks.append(.image(altText: "image"))
            default:
                continue
            }
        }
        return blocks
    }

    /// Flatten a `tool_result.content` (string, or array of text/image blocks)
    /// into display text. Base64 image data is dropped to a placeholder.
    private static func flattenResult(_ content: Any?) -> String {
        let text: String
        if let s = content as? String {
            text = s
        } else if let array = content as? [[String: Any]] {
            text = array.map { block -> String in
                switch block["type"] as? String {
                case "text": return (block["text"] as? String) ?? ""
                case "image": return "[image]"
                default: return ""
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        } else {
            text = ""
        }
        return truncate(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Build a compact, single-line summary of a tool's input for the header
    /// of a tool card (e.g. `rg "foo"`, `src/auth/login.ts`).
    private static func summarizeToolInput(name: String, input: Any?) -> String {
        guard let dict = input as? [String: Any] else { return "" }

        func str(_ key: String) -> String? {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let summary: String?
        switch name {
        case "Bash":
            summary = str("command")
        case "Read", "Edit", "Write", "NotebookEdit":
            summary = str("file_path") ?? str("path")
        case "Grep":
            summary = [str("pattern"), str("path")].compactMap { $0 }.joined(separator: "  ")
        case "Glob":
            summary = str("pattern")
        case "WebFetch", "WebSearch":
            summary = str("url") ?? str("query")
        case "Task":
            summary = str("description") ?? str("subagent_type")
        default:
            // Fall back to the most descriptive common field, else compact JSON.
            summary = str("description") ?? str("prompt") ?? str("command")
                ?? str("file_path") ?? str("pattern") ?? str("query")
        }

        let result = (summary?.isEmpty == false) ? summary! : compactJSON(dict)
        return truncate(result.replacingOccurrences(of: "\n", with: " "), max: 200)
    }

    // MARK: - Helpers

    private static func compactJSON(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else { return "" }
        return string
    }

    private static func truncate(_ text: String, max: Int = maxToolResultChars) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter.transcript.date(from: string)
    }
}

private extension ISO8601DateFormatter {
    /// Claude Code stamps timestamps with fractional seconds (e.g.
    /// `2026-06-14T18:42:11.123Z`).
    static let transcript: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
