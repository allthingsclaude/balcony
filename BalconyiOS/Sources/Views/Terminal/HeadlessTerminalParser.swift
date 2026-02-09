import Foundation
import SwiftTerm
import Combine

/// Parses raw PTY bytes using SwiftTerm's headless `Terminal` and extracts
/// conversation lines with styling for the SwiftUI renderer.
///
/// The terminal size is fixed to the Mac's PTY size so no resize events are sent,
/// preserving the Mac's terminal layout. Scrollback is enabled so the full
/// conversation history is available when replaying buffered PTY data.
@MainActor
final class HeadlessTerminalParser: ObservableObject {
    @Published var conversationLines: [TerminalLine] = []

    private let terminal: Terminal
    private let delegate: MinimalTerminalDelegate

    /// Throttle extraction to ~20fps.
    private var extractionScheduled = false

    init(cols: Int, rows: Int) {
        var options = TerminalOptions()
        options.cols = cols
        options.rows = rows
        options.scrollback = 5000
        // Keep the delegate alive — Terminal holds it weakly.
        self.delegate = MinimalTerminalDelegate()
        self.terminal = Terminal(delegate: delegate, options: options)
    }

    // MARK: - Feeding Data

    /// Feed raw PTY bytes into the terminal emulator.
    func feed(bytes: [UInt8]) {
        terminal.feed(byteArray: bytes)
        scheduleExtraction()
    }

    private func scheduleExtraction() {
        guard !extractionScheduled else { return }
        extractionScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.extractionScheduled = false
            self?.extractLines()
        }
    }

    // MARK: - Line Extraction

    private func extractLines() {
        let topVisible = terminal.getTopVisibleRow()
        let totalRows = topVisible + terminal.rows

        // Collect all lines (scrollback + visible) via public API.
        var allRows: [BufferLine] = []
        for row in 0..<totalRows {
            if let line = terminal.getScrollInvariantLine(row: row) {
                allRows.append(line)
            }
        }

        guard !allRows.isEmpty else {
            conversationLines = []
            return
        }

        let headerEnd = detectHeaderEnd(allRows: allRows)
        let chromeStart = detectChromeStart(allRows: allRows)

        guard headerEnd < chromeStart else {
            conversationLines = []
            return
        }

        var lines: [TerminalLine] = []
        var lineId = 0
        let cols = terminal.cols

        for i in headerEnd..<chromeStart {
            var segments = extractSegments(from: allRows[i])
            segments = replaceSymbols(segments)

            // Detect terminal-wrapped lines: previous line filled all columns.
            let prevWrapped = i > headerEnd &&
                allRows[i - 1].getTrimmedLength() >= cols

            // Strip Claude Code's 2-space continuation indent from all lines.
            segments = stripLeadingSpaces(segments, maxCount: 2)

            if prevWrapped, !lines.isEmpty {
                // Join with previous line (terminal soft-wrap).
                var joined = lines[lines.count - 1].segments
                joined.append(contentsOf: segments)
                lines[lines.count - 1] = TerminalLine(
                    id: lines[lines.count - 1].id, segments: joined, isWrapped: true
                )
            } else {
                lines.append(TerminalLine(
                    id: lineId, segments: segments, isWrapped: false
                ))
                lineId += 1
            }
        }

        // Trim trailing empty lines.
        while let last = lines.last, last.segments.isEmpty ||
              (last.segments.count == 1 && last.segments[0].text.trimmingCharacters(in: .whitespaces).isEmpty) {
            lines.removeLast()
            if lines.isEmpty { break }
        }

        conversationLines = lines
    }

    // MARK: - Chrome Detection

    /// Skip the top header (Claude Code welcome banner, ASCII art logo, version info).
    ///
    /// Scans for the first conversation marker: ❯ (user) or ⏺ (assistant).
    /// Everything before that is header chrome. Uses unicode scalar comparison
    /// to handle variation selectors (U+FE0F) that iOS may attach.
    private func detectHeaderEnd(allRows: [BufferLine]) -> Int {
        let scanLimit = min(50, allRows.count)

        for i in 0..<scanLimit {
            let text = allRows[i].translateToString(trimRight: true)
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Check the first unicode scalar (ignores variation selectors).
            guard let first = trimmed.unicodeScalars.first else { continue }
            if first == "\u{276F}" || first == "\u{23FA}" { // ❯ or ⏺
                return i
            }
        }
        return 0
    }

    /// Find the bottom chrome block (input box + status bar) using a forward scan.
    ///
    /// Scans for the LAST "box-drawing → ❯ → box-drawing" sandwich pattern.
    /// Everything from that opening box-drawing row to the end is chrome.
    private func detectChromeStart(allRows: [BufferLine]) -> Int {
        let count = allRows.count

        // Find the last non-empty row.
        var lastNonEmpty = -1
        for i in stride(from: count - 1, through: 0, by: -1) {
            let text = allRows[i].translateToString(trimRight: true)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                lastNonEmpty = i
                break
            }
        }
        guard lastNonEmpty >= 0 else { return count }
        let contentEnd = lastNonEmpty + 1

        // Forward scan: find the LAST "box → ❯ → box" sandwich.
        var chromeBoundary = contentEnd

        for i in 0..<contentEnd {
            let text = allRows[i].translateToString(trimRight: true)
            guard isChromeRow(text, minLength: 10) else { continue }

            // Found a box-drawing row. Look ahead for ❯ then another box-drawing row.
            let scanEnd = min(i + 8, contentEnd)
            var foundPrompt = false

            for j in (i + 1)..<scanEnd {
                let nextText = allRows[j].translateToString(trimRight: true)
                let nextTrimmed = nextText.trimmingCharacters(in: .whitespaces)

                if !foundPrompt {
                    // Looking for the ❯ prompt line inside the box.
                    if nextTrimmed.contains("❯") || nextTrimmed.contains("\u{276F}") {
                        foundPrompt = true
                    } else if isChromeRow(nextText, minLength: 10) ||
                              nextTrimmed.isEmpty ||
                              nextTrimmed.hasPrefix("│") ||
                              nextTrimmed.hasPrefix("┃") {
                        continue // box content, empty lines, or more box-drawing
                    } else {
                        break // real content — not the input chrome box
                    }
                } else {
                    // Found ❯, now looking for the closing box-drawing row.
                    if isChromeRow(nextText, minLength: 10) {
                        // Sandwich complete: box → ❯ → box. Record as chrome boundary.
                        chromeBoundary = i
                        break
                    } else if nextTrimmed.isEmpty ||
                              nextTrimmed.hasPrefix("│") ||
                              nextTrimmed.hasPrefix("┃") {
                        continue // box content or empty lines after ❯
                    } else {
                        break // non-box content after ❯ — not the input chrome
                    }
                }
            }
        }

        return chromeBoundary
    }

    /// Check if a row consists mostly of box-drawing characters (─ U+2500 and similar).
    private func isChromeRow(_ text: String, minLength: Int) -> Bool {
        let boxChars: Set<Character> = [
            "\u{2500}", "\u{2501}", "\u{2502}", "\u{2503}", // ─ ━ │ ┃
            "\u{250C}", "\u{250D}", "\u{250E}", "\u{250F}", // ┌ ┍ ┎ ┏
            "\u{2510}", "\u{2511}", "\u{2512}", "\u{2513}", // ┐ ┑ ┒ ┓
            "\u{2514}", "\u{2515}", "\u{2516}", "\u{2517}", // └ ┕ ┖ ┗
            "\u{2518}", "\u{2519}", "\u{251A}", "\u{251B}", // ┘ ┙ ┚ ┛
            "\u{251C}", "\u{2524}", "\u{252C}", "\u{2534}", // ├ ┤ ┬ ┴
            "\u{253C}",                                       // ┼
            "\u{256D}", "\u{256E}", "\u{256F}", "\u{2570}", // ╭ ╮ ╯ ╰
        ]

        guard text.count >= minLength else { return false }
        let boxCount = text.filter { boxChars.contains($0) }.count
        // Consider it chrome if >50% of non-space chars are box-drawing.
        let nonSpace = text.filter { !$0.isWhitespace }.count
        guard nonSpace > 0 else { return false }
        return Double(boxCount) / Double(nonSpace) > 0.5
    }

    // MARK: - Post-Processing

    /// Replace emoji-style symbols with simpler Unicode equivalents for mobile.
    /// ⏺ (U+23FA) → ● (U+25CF), ❯ (U+276F) → › (U+203A)
    private func replaceSymbols(_ segments: [StyledSegment]) -> [StyledSegment] {
        segments.map { seg in
            let replaced = seg.text
                .replacingOccurrences(of: "\u{23FA}", with: "\u{00B7}")
                .replacingOccurrences(of: "\u{276F}", with: "\u{203A}")
            guard replaced != seg.text else { return seg }
            return StyledSegment(text: replaced, style: seg.style)
        }
    }

    /// Strip up to `maxCount` leading space characters from the first segment(s).
    private func stripLeadingSpaces(_ segments: [StyledSegment], maxCount: Int) -> [StyledSegment] {
        guard maxCount > 0, !segments.isEmpty else { return segments }
        var result = segments
        var remaining = maxCount

        for idx in result.indices {
            let text = result[idx].text
            var stripped = text[text.startIndex...]
            while remaining > 0, stripped.first == " " {
                stripped = stripped.dropFirst()
                remaining -= 1
            }
            if stripped.isEmpty && idx < result.count - 1 {
                // Entire segment was spaces — remove it and continue to next.
                result[idx] = StyledSegment(text: "", style: result[idx].style)
            } else {
                result[idx] = StyledSegment(text: String(stripped), style: result[idx].style)
                break
            }
        }
        // Remove any empty segments we created.
        return result.filter { !$0.text.isEmpty }
    }

    // MARK: - Segment Extraction

    private func extractSegments(from bufferLine: BufferLine) -> [StyledSegment] {
        let trimmedLen = bufferLine.getTrimmedLength()
        guard trimmedLen > 0 else { return [] }

        var segments: [StyledSegment] = []
        var currentText = ""
        var currentStyle = SegmentStyle()
        var isFirst = true

        var col = 0
        while col < trimmedLen {
            let charData = bufferLine[col]
            // Null cells represent unwritten positions — render as spaces.
            let rawCh = terminal.getCharacter(for: charData)
            let ch: Character = rawCh == "\0" ? " " : rawCh
            let style = mapStyle(charData.attribute)

            if isFirst {
                currentStyle = style
                isFirst = false
            }

            if style == currentStyle {
                currentText.append(ch)
            } else {
                if !currentText.isEmpty {
                    segments.append(StyledSegment(text: currentText, style: currentStyle))
                }
                currentText = String(ch)
                currentStyle = style
            }

            // Skip trailing null cells for wide characters.
            let width = max(1, Int(charData.width))
            col += width
        }

        if !currentText.isEmpty {
            segments.append(StyledSegment(text: currentText, style: currentStyle))
        }

        return segments
    }

    /// Map SwiftTerm's Attribute to our SegmentStyle.
    private func mapStyle(_ attr: Attribute) -> SegmentStyle {
        SegmentStyle(
            fgColor: mapColor(attr.fg, isBackground: false),
            bgColor: mapColor(attr.bg, isBackground: true),
            isBold: attr.style.contains(.bold),
            isItalic: attr.style.contains(.italic),
            isUnderline: attr.style.contains(.underline),
            isDim: attr.style.contains(.dim)
        )
    }

    /// Map SwiftTerm's Attribute.Color to our ANSIColor.
    private func mapColor(_ color: Attribute.Color, isBackground: Bool) -> ANSIColor {
        switch color {
        case .defaultColor:
            return isBackground ? .defaultBg : .defaultFg
        case .defaultInvertedColor:
            // As bg: use the fg semantic color (dark in light mode).
            // As fg: also use fg semantic so text stays visible — we don't render
            // bg colors so the "inverted" visual is lost anyway.
            return .defaultFg
        case .ansi256(let code):
            return .palette(code)
        case .trueColor(let r, let g, let b):
            return .rgb(r, g, b)
        }
    }
}

// MARK: - Minimal Delegate

/// A no-op delegate to satisfy SwiftTerm's Terminal requirement.
/// Terminal holds delegate weakly, so this must be retained by the parser.
private final class MinimalTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
        // No-op: we don't send data back to the host from the parser.
    }
}
