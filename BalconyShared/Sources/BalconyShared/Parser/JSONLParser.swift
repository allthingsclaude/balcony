import Foundation

/// Result of parsing a single JSONL line, including optional metadata.
public struct ParsedEntry: Sendable {
    public let message: SessionMessage?
    public let cwd: String?
    public let sessionId: String?
}

/// Stream-based parser for Claude Code JSONL session files.
public struct JSONLParser: Sendable {

    public init() {}

    // MARK: - Public API

    /// Parse all complete lines from JSONL data, returning only messages.
    public func parse(_ data: Data) -> [SessionMessage] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Parse all complete lines from a JSONL string, returning only messages.
    public func parse(_ text: String) -> [SessionMessage] {
        text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { parseLine($0) }
    }

    /// Parse a single JSONL line into a SessionMessage.
    public func parseLine(_ line: String) -> SessionMessage? {
        parseEntry(line).message
    }

    /// Parse a single JSONL line into a full ParsedEntry (message + metadata).
    public func parseEntry(_ line: String) -> ParsedEntry {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedEntry(message: nil, cwd: nil, sessionId: nil)
        }

        let cwd = json["cwd"] as? String
        let sessionId = json["sessionId"] as? String ?? json["session_id"] as? String

        guard let typeStr = json["type"] as? String else {
            return ParsedEntry(message: nil, cwd: cwd, sessionId: sessionId)
        }

        // Skip non-message types
        let skipTypes: Set<String> = ["progress", "file-history-snapshot", "system"]
        guard !skipTypes.contains(typeStr) else {
            return ParsedEntry(message: nil, cwd: cwd, sessionId: sessionId)
        }

        // Map type to role
        let role: MessageRole
        switch typeStr {
        case "user":
            role = .user
        case "human":
            role = .human
        case "assistant":
            role = .assistant
        case "tool_use":
            role = .toolUse
        case "tool_result":
            role = .toolResult
        default:
            return ParsedEntry(message: nil, cwd: cwd, sessionId: sessionId)
        }

        // Skip meta messages (internal commands like /fast, local-command-stdout, etc.)
        if let isMeta = json["isMeta"] as? Bool, isMeta {
            return ParsedEntry(message: nil, cwd: cwd, sessionId: sessionId)
        }

        // Extract content - real format nests it under "message"
        let content = extractContent(from: json)

        // Skip empty content
        guard !content.isEmpty else {
            return ParsedEntry(message: nil, cwd: cwd, sessionId: sessionId)
        }

        let timestamp = parseTimestamp(from: json)

        let message = SessionMessage(
            sessionId: sessionId ?? "unknown",
            role: role,
            content: content,
            timestamp: timestamp
        )

        return ParsedEntry(message: message, cwd: cwd, sessionId: sessionId)
    }

    /// Parse all lines returning full entries (messages + metadata).
    public func parseEntries(_ text: String) -> [ParsedEntry] {
        text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { parseEntry($0) }
    }

    // MARK: - Content Extraction

    private func extractContent(from json: [String: Any]) -> String {
        // Real Claude Code format: content is at json["message"]["content"]
        if let messageDict = json["message"] as? [String: Any] {
            return extractContentValue(from: messageDict)
        }

        // Legacy/simple format: content at top level
        return extractContentValue(from: json)
    }

    private func extractContentValue(from dict: [String: Any]) -> String {
        if let content = dict["content"] as? String {
            return content
        }

        if let contentArray = dict["content"] as? [[String: Any]] {
            return extractFromContentBlocks(contentArray)
        }

        return ""
    }

    private func extractFromContentBlocks(_ blocks: [[String: Any]]) -> String {
        var parts: [String] = []

        for block in blocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    parts.append(text)
                }

            case "tool_use":
                let name = block["name"] as? String ?? "unknown"
                var summary = "[Tool: \(name)]"
                if let input = block["input"] as? [String: Any] {
                    // Show first useful field from input
                    if let filePath = input["file_path"] as? String {
                        summary += " \(filePath)"
                    } else if let command = input["command"] as? String {
                        summary += " \(String(command.prefix(100)))"
                    } else if let query = input["query"] as? String {
                        summary += " \(String(query.prefix(100)))"
                    } else if let pattern = input["pattern"] as? String {
                        summary += " \(pattern)"
                    }
                }
                parts.append(summary)

            case "tool_result":
                if let content = block["content"] as? String {
                    let truncated = content.count > 200 ? String(content.prefix(200)) + "..." : content
                    parts.append("[Result] \(truncated)")
                }

            default:
                break
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Timestamp Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func parseTimestamp(from json: [String: Any]) -> Date {
        guard let ts = json["timestamp"] as? String else { return Date() }
        // Try fractional seconds first (most common in real data)
        if let date = Self.fractionalFormatter.date(from: ts) {
            return date
        }
        if let date = Self.isoFormatter.date(from: ts) {
            return date
        }
        return Date()
    }
}
