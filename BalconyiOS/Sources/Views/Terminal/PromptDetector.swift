import Foundation

/// Pure-function detection of interactive prompts from parsed terminal lines.
///
/// After HeadlessTerminalParser processing:
/// - `❯` (U+276F) is replaced with `›` (U+203A)
/// - Up to 2 leading spaces are stripped from non-table lines
///
/// So a Claude Code option list like:
/// ```
///   ❯ 1. Yes
///     2. Yes, and don't ask again
///     3. No (esc)
/// ```
/// Becomes parsed lines:
/// ```
///   › 1. Yes
///   2. Yes, and don't ask again
///   3. No (esc)
/// ```
enum PromptDetector {

    /// Detection result containing the prompt and where to strip terminal lines.
    struct Result {
        let prompt: InteractivePrompt
        /// Lines from this index to the end should be removed from display
        /// (the prompt is shown natively instead).
        let stripFromIndex: Int
    }

    /// Analyze the tail of conversation lines and return a detected prompt, if any.
    static func detect(in lines: [TerminalLine]) -> Result? {
        // Try multi-option first (covers numbered permission prompts too),
        // then fall back to inline permission format.
        if let result = detectMultiOption(in: lines) {
            return result
        }
        if let result = detectPermission(in: lines) {
            return result
        }
        return nil
    }

    // MARK: - Permission Detection

    /// Scan last 15 lines for a "(X)word / (Y)word" inline pattern.
    private static func detectPermission(in lines: [TerminalLine]) -> Result? {
        let tailCount = min(15, lines.count)
        let startIdx = lines.count - tailCount

        let optionPattern = #/\(([A-Za-z])\)(\w+)/#

        for lineIdx in startIdx..<lines.count {
            let text = plainText(from: lines[lineIdx])
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard trimmed.contains("("), trimmed.contains("/") else { continue }

            let parts = trimmed.components(separatedBy: " / ")
            guard parts.count >= 2 else { continue }

            var options: [PermissionOption] = []

            for (i, part) in parts.enumerated() {
                let partTrimmed = part.trimmingCharacters(in: .whitespaces)

                if let match = partTrimmed.firstMatch(of: optionPattern) {
                    let letter = String(match.1)
                    let wordStart = String(match.2)

                    let matchEnd = match.range.upperBound
                    let rest = String(partTrimmed[matchEnd...]).trimmingCharacters(in: .whitespaces)
                    let fullLabel = rest.isEmpty ? wordStart : wordStart + " " + rest

                    let isDestructive = isDestructiveLabel(fullLabel)

                    options.append(PermissionOption(
                        label: fullLabel,
                        inputToSend: letter.lowercased(),
                        isDefault: i == 0,
                        isDestructive: isDestructive
                    ))
                }
            }

            if options.count >= 2 {
                return Result(
                    prompt: .permission(PermissionPrompt(options: options)),
                    stripFromIndex: lineIdx
                )
            }
        }

        return nil
    }

    private static func isDestructiveLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        let destructiveWords = ["no", "deny", "don't", "dont", "reject", "refuse", "block"]
        return destructiveWords.contains { lower.hasPrefix($0) || lower.contains($0) }
    }

    // MARK: - Multi-Option Detection

    /// Scan last 20 lines for a numbered option group.
    ///
    /// After HeadlessTerminalParser processing, the lines look like:
    /// - Selected:   `› 1. Yes` (› prefix from ❯ symbol replacement)
    /// - Unselected: `2. Yes, and don't ask again` (leading spaces stripped)
    /// - Unselected: `3. No, and tell Claude what to do differently (esc)`
    ///
    /// Detection matches consecutive lines with `N. text` or `› N. text` patterns.
    private static func detectMultiOption(in lines: [TerminalLine]) -> Result? {
        let tailCount = min(20, lines.count)
        guard tailCount >= 3 else { return nil }

        let startIdx = lines.count - tailCount
        let tail = Array(lines[startIdx...])

        // Scan backward from end, collecting consecutive numbered option lines.
        var entries: [(text: String, isSelected: Bool, tailIdx: Int)] = []

        for i in stride(from: tail.count - 1, through: 0, by: -1) {
            let text = plainText(from: tail[i])
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            // Empty lines break the option group.
            if trimmed.isEmpty {
                if !entries.isEmpty { break }
                continue
            }

            if let parsed = parseNumberedOption(trimmed) {
                entries.insert((parsed.text, parsed.isSelected, i), at: 0)
            } else {
                // Not an option line — stop if we already collected some.
                if !entries.isEmpty { break }
            }
        }

        // Require 2+ options with exactly 1 selected.
        guard entries.count >= 2 else { return nil }
        let selectedCount = entries.filter(\.isSelected).count
        guard selectedCount == 1 else { return nil }

        // Verify numbering is sequential (1, 2, 3...).
        let numbers = entries.compactMap { entry -> Int? in
            let text = entry.isSelected
                ? plainText(from: tail[entry.tailIdx]).trimmingCharacters(in: .whitespaces)
                    .drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
                : plainText(from: tail[entry.tailIdx]).trimmingCharacters(in: .whitespaces)
                    .prefix(while: { $0.isNumber })
            return Int(text)
        }
        guard numbers.count == entries.count else { return nil }
        for (i, num) in numbers.enumerated() {
            if num != i + 1 { return nil }
        }

        // Find question text and the strip boundary.
        // Strip from the question line (inclusive) through all option lines.
        let firstOptionAbsIdx = startIdx + entries[0].tailIdx
        var question = ""
        var stripFrom = firstOptionAbsIdx

        if firstOptionAbsIdx > 0 {
            // Scan backward past empty lines to find question text.
            for i in stride(from: firstOptionAbsIdx - 1, through: max(0, firstOptionAbsIdx - 5), by: -1) {
                let text = plainText(from: lines[i]).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    question = text
                    stripFrom = i
                    break
                }
            }
        }

        // Build option items.
        var items: [MultiOptionItem] = []
        var selectedIndex = 0

        for (idx, entry) in entries.enumerated() {
            var label = entry.text
            var isRecommended = false

            // Strip "(esc)" suffix.
            if label.hasSuffix("(esc)") {
                label = String(label.dropLast(5)).trimmingCharacters(in: .whitespaces)
            }

            // Detect "(Recommended)" suffix.
            if label.hasSuffix("(Recommended)") {
                label = String(label.dropLast(13)).trimmingCharacters(in: .whitespaces)
                isRecommended = true
            }

            let isOther = label.lowercased() == "other"

            if entry.isSelected {
                selectedIndex = idx
            }

            items.append(MultiOptionItem(
                label: label,
                isRecommended: isRecommended,
                isOther: isOther,
                index: idx
            ))
        }

        let prompt = MultiOptionPrompt(
            question: question,
            options: items,
            selectedIndex: selectedIndex
        )

        return Result(
            prompt: .multiOption(prompt),
            stripFromIndex: stripFrom
        )
    }

    /// Parse a line as a numbered option.
    ///
    /// Matches:
    /// - `› N. text` — selected (› from ❯ symbol replacement)
    /// - `N. text`   — unselected (leading spaces already stripped)
    private static func parseNumberedOption(_ trimmed: String) -> (text: String, isSelected: Bool)? {
        // Selected: starts with › then optional space then "N. "
        if let first = trimmed.unicodeScalars.first,
           first == Unicode.Scalar(0x203A) {
            var rest = String(trimmed.dropFirst())
            if rest.hasPrefix(" ") { rest = String(rest.dropFirst()) }
            if let dotIdx = rest.firstIndex(of: "."),
               let num = Int(rest[rest.startIndex..<dotIdx]),
               num > 0 {
                let afterDot = rest[rest.index(after: dotIdx)...]
                let text = afterDot.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }
                return (text, true)
            }
            return nil
        }

        // Unselected: starts with "N. text"
        if let first = trimmed.first, first.isNumber {
            if let dotIdx = trimmed.firstIndex(of: "."),
               let num = Int(trimmed[trimmed.startIndex..<dotIdx]),
               num > 0 {
                let afterDot = trimmed[trimmed.index(after: dotIdx)...]
                let text = afterDot.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }
                return (text, false)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func plainText(from line: TerminalLine) -> String {
        line.segments.map(\.text).joined()
    }
}
