import Foundation

/// Stream-based parser for Claude Code JSONL session files.
public struct JSONLParser: Sendable {
    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Parse all complete lines from JSONL data.
    /// Skips malformed lines and incomplete trailing lines.
    public func parse(_ data: Data) -> [SessionMessage] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return parse(text)
    }

    /// Parse all complete lines from a JSONL string.
    public func parse(_ text: String) -> [SessionMessage] {
        text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                parseLine(line)
            }
    }

    /// Parse a single JSONL line into a SessionMessage.
    public func parseLine(_ line: String) -> SessionMessage? {
        guard let data = line.data(using: .utf8) else { return nil }

        do {
            // Try direct decoding first
            return try decoder.decode(SessionMessage.self, from: data)
        } catch {
            // Try parsing as raw JSON and mapping fields
            return parseRawLine(data)
        }
    }

    /// Attempt to parse a line as raw JSON and map to SessionMessage.
    private func parseRawLine(_ data: Data) -> SessionMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let typeStr = json["type"] as? String,
              let role = MessageRole(rawValue: typeStr) else {
            return nil
        }

        let content: String
        if let c = json["content"] as? String {
            content = c
        } else if let c = json["content"] as? [[String: Any]] {
            // Claude API format: content is array of blocks
            content = c.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            content = ""
        }

        let sessionId = json["session_id"] as? String ?? "unknown"
        let timestamp: Date
        if let ts = json["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
        } else {
            timestamp = Date()
        }

        return SessionMessage(
            sessionId: sessionId,
            role: role,
            content: content,
            timestamp: timestamp
        )
    }
}
