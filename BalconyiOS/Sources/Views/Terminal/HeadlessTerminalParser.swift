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
    @Published var activePrompt: InteractivePrompt?

    /// Text currently typed after the ❯ prompt in the bottom chrome input box.
    /// Used to pre-fill the iOS input composer when entering a session.
    @Published var pendingInputText: String = ""

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

        // Always extract chrome input — even when there's no conversation content
        // (e.g. a freshly-opened thread with only the welcome banner).
        pendingInputText = extractChromeInputText(allRows: allRows, chromeStart: chromeStart)

        guard headerEnd < chromeStart else {
            conversationLines = []
            return
        }

        let cols = terminal.cols
        let count = chromeStart - headerEnd

        // Phase 1: Extract segments and classify each row.
        //
        // Classification uses a *structural* approach — no fraction thresholds.
        //
        //   strongCode — 2+ distinct non-default fg colors, OR non-default bg
        //   weakCode   — code pattern (.foo, }, //) OR exactly 1 non-default color
        //   neutral    — empty / whitespace-only
        //   prose      — 0 non-default colors, structural prefixes, markers

        enum CodeSignal { case strongCode, weakCode, neutral, prose }

        var rowSegments: [[StyledSegment]] = []
        var rowIsTable = [Bool](repeating: false, count: count)
        var rowSignal = [CodeSignal](repeating: .neutral, count: count)
        var rowOrigLen = [Int](repeating: 0, count: count)
        var rowMarker = [MarkerRole](repeating: .none, count: count)

        for i in 0..<count {
            let ri = headerEnd + i
            var segments = extractSegments(from: allRows[ri])

            // Detect conversation markers from ORIGINAL characters before symbol
            // replacement.  ❯ (U+276F) = user, ⏺ (U+23FA) = assistant.
            // Spinner frames (✳ etc.) also sometimes land on ⏺, so we require
            // the marker character to have a non-bright ANSI style: the real
            // Claude Code markers use dim/magenta while spinners use bright
            // colors.
            // Scan past leading space segments to find the actual marker character.
            // Assistant markers (⏺) may be indented with spaces in a separate
            // ANSI style segment, so checking only segments.first would miss them.
            var markerScalar: Unicode.Scalar?
            var markerStyle: SegmentStyle?
            outer: for seg in segments {
                for scalar in seg.text.unicodeScalars {
                    if scalar != " " && scalar != "\0" {
                        markerScalar = scalar
                        markerStyle = seg.style
                        break outer
                    }
                }
            }

            if let scalar = markerScalar, let style = markerStyle {
                if scalar == Unicode.Scalar(0x276F) {   // ❯ user
                    rowMarker[i] = .user
                } else if scalar == Unicode.Scalar(0x23FA) {  // ⏺ assistant
                    // Reject only spinner-like ⏺: bold and not dim.
                    // Real assistant markers use dim, default, magenta (palette
                    // or trueColor) — never bold. Spinners are bold+bright.
                    let isSpinner = style.isBold && !style.isDim
                    if !isSpinner {
                        rowMarker[i] = .assistant
                    }
                }
            }

            segments = replaceSymbols(segments)

            let isTable = containsBoxDrawing(segments)
            if !isTable {
                segments = stripLeadingSpaces(segments, maxCount: .max)
            }

            rowSegments.append(segments)
            rowIsTable[i] = isTable
            rowOrigLen[i] = allRows[ri].getTrimmedLength()

            // Classify this row.
            if isTable {
                rowSignal[i] = .neutral // tables handled separately
                continue
            }

            let empty = segments.isEmpty ||
                segments.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            if empty {
                rowSignal[i] = .neutral
                continue
            }

            guard let first = segments.first, !first.text.isEmpty else {
                rowSignal[i] = .neutral
                continue
            }

            let firstChar = first.text.first!

            // Markers (› ·) → always prose (message boundary).
            if rowMarker[i] != .none ||
               firstChar == "\u{203A}" || firstChar == "\u{00B7}" {
                rowSignal[i] = .prose
                continue
            }

            // Structural prefixes (#, -, *, >, etc.) → prose even if colored.
            if "#-*>|+`~@".contains(firstChar) {
                rowSignal[i] = .prose
                continue
            }

            // Count distinct non-default fg colors (no fraction threshold).
            var nonDefaultColors = Set<ANSIColor>()
            for seg in segments {
                if seg.style.fgColor != .defaultFg {
                    nonDefaultColors.insert(seg.style.fgColor)
                }
            }

            if hasNonDefaultBackground(segments) || nonDefaultColors.count >= 2 {
                rowSignal[i] = .strongCode
            } else if looksLikeCodeLine(segments) || nonDefaultColors.count == 1 {
                rowSignal[i] = .weakCode
            } else {
                rowSignal[i] = .prose
            }
        }

        // Phase 2: Code block detection using core-expand-merge.
        //
        // Step 1 (Core): Find consecutive runs of strongCode lines.
        // Step 2 (Expand): From each core edge, absorb adjacent weakCode lines.
        //                   Stop at neutral (empty) or prose lines — empty lines
        //                   are the natural boundary Claude Code places between
        //                   code blocks and prose.
        // Step 3 (Merge): Reconnect expanded blocks separated by ≤2 neutral lines
        //                  (handles blank lines inside code blocks like between
        //                  function definitions).
        //
        // This avoids fraction thresholds entirely. The key insight is that
        // Claude Code always puts empty lines between code blocks and surrounding
        // text, so expansion naturally stops at the right boundary.

        var isCodeBlock = [Bool](repeating: false, count: count)

        // Step 1: Mark core blocks (consecutive strongCode).
        for i in 0..<count {
            if rowSignal[i] == .strongCode && !rowIsTable[i] {
                isCodeBlock[i] = true
            }
        }

        // Step 2: Expand each core block to absorb adjacent weakCode.
        // Scan forward and backward from each marked edge.
        var changed = true
        while changed {
            changed = false
            for i in 0..<count {
                guard isCodeBlock[i] else { continue }

                // Expand forward: if next line is weakCode and not yet marked.
                if i + 1 < count && !isCodeBlock[i + 1] &&
                   !rowIsTable[i + 1] && rowSignal[i + 1] == .weakCode {
                    isCodeBlock[i + 1] = true
                    changed = true
                }

                // Expand backward: if previous line is weakCode and not yet marked.
                if i - 1 >= 0 && !isCodeBlock[i - 1] &&
                   !rowIsTable[i - 1] && rowSignal[i - 1] == .weakCode {
                    isCodeBlock[i - 1] = true
                    changed = true
                }
            }
        }

        // Step 3: Merge blocks separated by small neutral gaps (≤2 lines).
        // This handles blank lines inside code blocks (e.g., between functions).
        for i in 0..<count {
            guard isCodeBlock[i] else { continue }

            // Look ahead past neutral gap.
            var j = i + 1
            while j < count && rowSignal[j] == .neutral && !rowIsTable[j] && j - i <= 3 {
                j += 1
            }

            // If we hit another code block within the gap limit, fill the gap.
            if j < count && j - i <= 3 && isCodeBlock[j] {
                for k in (i + 1)..<j {
                    if rowSignal[k] == .neutral && !rowIsTable[k] {
                        isCodeBlock[k] = true
                    }
                }
            }
        }

        // Phase 3: Build output lines.
        var lines: [TerminalLine] = []
        var lineId = 0
        var lastOriginalLength = 0

        for i in 0..<count {
            let segments = rowSegments[i]
            let isPreformatted = rowIsTable[i] || isCodeBlock[i]

            // Detect terminal-wrapped lines: previous line filled all columns.
            // Guard: rows that start a new content element (marker or structural
            // symbol like ⎿) are never soft-wrap continuations — Claude Code's TUI
            // pads rows to full width, making rowOrigLen == cols for most rows.
            let startsNewContent = rowMarker[i] != .none
                || segments.first.map { seg in
                    guard let ch = seg.text.first else { return false }
                    return !ch.isASCII && !ch.isLetter
                } ?? false
            let prevWrapped = !isPreformatted && i > 0 &&
                rowOrigLen[i - 1] >= cols && !startsNewContent

            if prevWrapped, !lines.isEmpty {
                // Terminal soft-wrap — join without extra space (break may be mid-word).
                let prev = lines[lines.count - 1]
                var joined = prev.segments
                joined.append(contentsOf: segments)
                lines[lines.count - 1] = TerminalLine(
                    id: prev.id, segments: joined, isWrapped: true,
                    markerRole: prev.markerRole
                )
            } else if !isPreformatted,
                      !lines.isEmpty,
                      !isEmptyLine(lines[lines.count - 1]),
                      isPreviousLineJoinable(lines[lines.count - 1]),
                      lastOriginalLength >= cols - 15,
                      isTextContinuation(segments) {
                // Claude's text wrap — join with space (break was at word boundary).
                let prev = lines[lines.count - 1]
                var joined = prev.segments
                if let lastIdx = joined.indices.last,
                   !joined[lastIdx].text.hasSuffix(" ") {
                    joined[lastIdx] = StyledSegment(
                        text: joined[lastIdx].text + " ",
                        style: joined[lastIdx].style
                    )
                }
                joined.append(contentsOf: segments)
                lines[lines.count - 1] = TerminalLine(
                    id: prev.id, segments: joined, isWrapped: true,
                    markerRole: prev.markerRole
                )
            } else {
                lines.append(TerminalLine(
                    id: lineId, segments: segments, isWrapped: false,
                    isTableRow: isPreformatted,
                    markerRole: rowMarker[i]
                ))
                lineId += 1
            }

            lastOriginalLength = rowOrigLen[i]
        }

        // Trim trailing empty lines.
        while let last = lines.last, last.segments.isEmpty ||
              (last.segments.count == 1 && last.segments[0].text.trimmingCharacters(in: .whitespaces).isEmpty) {
            lines.removeLast()
            if lines.isEmpty { break }
        }

        if let result = PromptDetector.detect(in: lines) {
            activePrompt = result.prompt
            // Strip the prompt lines — they're shown natively via PromptOverlayView.
            lines = Array(lines.prefix(result.stripFromIndex))
            // Trim trailing empty lines left after stripping.
            while let last = lines.last, last.segments.isEmpty ||
                  (last.segments.count == 1 && last.segments[0].text.trimmingCharacters(in: .whitespaces).isEmpty) {
                lines.removeLast()
                if lines.isEmpty { break }
            }
        } else {
            activePrompt = nil
        }

        conversationLines = lines

        // Update chrome input — re-extract since the terminal may have changed
        // between the early extraction and now (e.g. prompt detection stripped lines).
        pendingInputText = extractChromeInputText(allRows: allRows, chromeStart: chromeStart)
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

        // No conversation markers found. If the Claude Code header banner
        // is present (ASCII art ███), this is an empty/loading thread —
        // suppress all content to avoid flashing the header and mode hints.
        for i in 0..<scanLimit {
            let text = allRows[i].translateToString(trimRight: true)
            if text.contains("\u{2588}\u{2588}\u{2588}") { // ███ ASCII art
                return allRows.count
            }
        }
        return 0
    }

    /// Find the bottom chrome block (input box + status bar) using a forward scan
    /// over the bottom portion of the terminal.
    ///
    /// Scans for the LAST "box-drawing → ❯ → box-drawing" sandwich pattern.
    /// Everything from that opening box-drawing row to the end is chrome.
    ///
    /// The scan window is 30 rows (not 8) to handle tall input boxes when the
    /// user types multi-line text. After finding ❯, continuation lines are
    /// accepted regardless of whether they start with │ — the input box may
    /// not render side borders on every wrapped line.
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

        // Only scan the bottom portion — the input box is always at the end.
        let scanStart = max(0, contentEnd - 50)

        // Forward scan: find the LAST "box → ❯ → box" sandwich.
        var chromeBoundary = contentEnd

        for i in scanStart..<contentEnd {
            let text = allRows[i].translateToString(trimRight: true)
            guard isChromeRow(text, minLength: 10) else { continue }

            // Found a box-drawing row. Look ahead for ❯ then another box-drawing row.
            let scanEnd = min(i + 30, contentEnd)
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
                    // Accept any content between ❯ and the closing border —
                    // multi-line input may not have │ side borders on every row.
                    if isChromeRow(nextText, minLength: 10) {
                        // Sandwich complete: box → ❯ → box. Record as chrome boundary.
                        chromeBoundary = i
                        break
                    }
                }
            }
        }

        // Absorb the mode hint block that sits just above the input chrome.
        // Walk backward from chromeBoundary, absorbing:
        //   - blank/null-only lines
        //   - lines starting with ! or & (hint/tip lines)
        //   - separator lines (mostly non-alphanumeric)
        //
        // Note: terminal buffer rows often have leading null chars (\0) for
        // padding. We strip those alongside whitespace for accurate matching.
        let nullAndSpace = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\0"))

        var adjusted = chromeBoundary
        var k = adjusted - 1
        while k >= 0 {
            let text = allRows[k].translateToString(trimRight: true)
            let trimmed = text.trimmingCharacters(in: nullAndSpace)

            if trimmed.isEmpty {
                adjusted = k; k -= 1; continue
            }
            if let ch = trimmed.first, (ch == "!" || ch == "&"), trimmed.count < 60 {
                adjusted = k; k -= 1; continue
            }
            let symbolCount = trimmed.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && $0 != "\0" }.count
            if trimmed.count > 5 && symbolCount * 2 > trimmed.count {
                adjusted = k; k -= 1; continue
            }
            break
        }

        return adjusted
    }

    /// Extract the user's in-progress input from the chrome input box.
    ///
    /// The chrome section contains a box like:
    /// ```
    /// ┌──────────────────────────────┐
    /// │ ❯ user typed text here       │
    /// └──────────────────────────────┘
    /// ```
    /// This method finds the ❯ line and reads buffer cells up to the cursor
    /// column, which precisely marks where the user's text ends. This avoids
    /// both trimming the user's trailing space and including box padding.
    ///
    /// Placeholder text (e.g. "Type a message...") uses non-default foreground
    /// color or dim styling and is ignored — only real user input is returned.
    private func extractChromeInputText(allRows: [BufferLine], chromeStart: Int) -> String {
        guard chromeStart < allRows.count else { return "" }

        for i in chromeStart..<allRows.count {
            let bufLine = allRows[i]
            let trimmedLen = bufLine.getTrimmedLength()

            // Find ❯ column by scanning buffer cells.
            var promptCol = -1
            for col in 0..<trimmedLen {
                let ch = terminal.getCharacter(for: bufLine[col])
                if ch == "\u{276F}" {
                    promptCol = col
                    break
                }
            }
            guard promptCol >= 0 else { continue }

            // Skip ❯ and the space after it.
            var startCol = promptCol + 1
            if startCol < trimmedLen {
                let ch = terminal.getCharacter(for: bufLine[startCol])
                if ch == " " || ch == "\0" { startCol += 1 }
            }

            // No content after ❯ — empty input.
            guard startCol < trimmedLen else { return "" }

            // Placeholder detection: Claude Code placeholder text (e.g.
            // 'Try "fix lint errors"') uses mixed dim styling — some chars
            // dim, some not. Real user input never has dim characters.
            // Check the first several characters; if ANY are dim, it's placeholder.
            let scanEnd = min(startCol + 10, trimmedLen)
            for col in startCol..<scanEnd {
                let ch = terminal.getCharacter(for: bufLine[col])
                if ch == "\0" || ch == " " { continue }
                if bufLine[col].attribute.style.contains(.dim) {
                    return ""
                }
            }

            // Find end of user content by locating the TUI block cursor.
            // Claude Code renders the cursor as a cell with inverse video
            // (style includes bit for inverse/reverse), while all user-typed
            // text and padding have style=0. Scanning for the first cell with
            // non-zero style gives us the exact end-of-input column, including
            // any trailing spaces the user typed.
            var endCol = -1
            for col in startCol..<trimmedLen {
                let style = bufLine[col].attribute.style
                if style.rawValue != 0 && !style.contains(.dim) {
                    endCol = col
                    break
                }
            }

            if endCol < 0 {
                // No TUI cursor found (cursor hidden or off-screen) — fall
                // back to stripping trailing whitespace.
                endCol = trimmedLen
                while endCol > startCol {
                    let ch = terminal.getCharacter(for: bufLine[endCol - 1])
                    guard ch == " " || ch == "\0" else { break }
                    endCol -= 1
                }
            }

            guard endCol > startCol else { return "" }

            // Collect characters from the buffer cells.
            var result = ""
            for col in startCol..<endCol {
                let ch = terminal.getCharacter(for: bufLine[col])
                result.append(ch == "\0" ? " " : ch)
            }
            return result
        }

        return ""
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
    /// ⏺ (U+23FA) → · (U+00B7), ❯ (U+276F) → › (U+203A)
    private func replaceSymbols(_ segments: [StyledSegment]) -> [StyledSegment] {
        segments.map { seg in
            let replaced = seg.text
                .replacingOccurrences(of: "\u{23FA}", with: "\u{00B7}")  // ⏺ → ·
                .replacingOccurrences(of: "\u{276F}", with: "\u{203A}")  // ❯ → ›
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

    /// Check if segments contain box-drawing characters (table row).
    private func containsBoxDrawing(_ segments: [StyledSegment]) -> Bool {
        for seg in segments {
            for ch in seg.text.unicodeScalars {
                if ch.value >= 0x2500 && ch.value <= 0x257F { return true }
            }
        }
        return false
    }

    /// Check if any segment has a non-default background (code block indicator).
    private func hasNonDefaultBackground(_ segments: [StyledSegment]) -> Bool {
        segments.contains { $0.style.bgColor != .defaultBg }
    }

    /// Check if a line has code-like syntactic patterns that never start prose.
    /// Used as a weak signal for code block membership.
    private func looksLikeCodeLine(_ segments: [StyledSegment]) -> Bool {
        guard let first = segments.first, !first.text.isEmpty else { return false }
        let firstChar = first.text.first!
        // Method chaining (.foo), braces, brackets, closing delimiters.
        if ".{}()[];:".contains(firstChar) { return true }
        // Comments (// ...)
        if first.text.hasPrefix("//") { return true }
        return false
    }

    /// Check if the previous line's content allows text joining.
    /// Returns false for code endings, table rows, and other structural content.
    private func isPreviousLineJoinable(_ line: TerminalLine) -> Bool {
        if line.isTableRow { return false }
        let fullText = line.segments.map(\.text).joined()
        let trimmed = fullText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Don't join after lines ending with code/structural characters.
        if let last = trimmed.last, "{}[]();|".contains(last) { return false }
        // Don't join after table rows (box-drawing).
        for ch in trimmed.unicodeScalars {
            if ch.value >= 0x2500 && ch.value <= 0x257F { return false }
        }
        return true
    }

    /// Check if a line's segments represent empty/whitespace-only content.
    private func isEmptyLine(_ line: TerminalLine) -> Bool {
        line.segments.isEmpty ||
        line.segments.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Check if segments look like a text continuation (not code, list, heading, etc.).
    /// Used to join Claude Code's word-wrapped lines into flowing paragraphs.
    private func isTextContinuation(_ segments: [StyledSegment]) -> Bool {
        guard let first = segments.first, !first.text.isEmpty else { return false }
        let firstChar = first.text.first!

        // Marker = new message, not continuation.
        if firstChar == "\u{203A}" || firstChar == "\u{00B7}" { return false }
        // Leading whitespace = code block.
        if firstChar == " " || firstChar == "\t" { return false }
        // Non-ASCII symbols (⎿, ⏺, spinner chars, etc.) are structural, not prose.
        // Allow non-ASCII letters (CJK, Cyrillic, etc.) for multilingual text.
        if !firstChar.isASCII && !firstChar.isLetter { return false }
        // Structural prefixes (headings, lists, blockquotes, fences, diffs, comments).
        if "#-*>|+`~@/".contains(firstChar) { return false }
        // Numbered list: "1. " or "1) "
        if firstChar.isNumber {
            let rest = first.text.dropFirst()
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return false }
        }

        return true
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
