import Foundation

/// Role of the conversation marker at the start of a terminal line.
enum MarkerRole: Equatable {
    case user       // ❯ / › — user message start
    case assistant  // ⏺ / · — assistant message start
    case spinner    // ✶ ✻ ✢ · ✽ — animated progress indicator
    case none       // continuation or non-message line
}

/// A single line of parsed terminal output with styled segments.
struct TerminalLine: Identifiable, Equatable {
    let id: Int
    let segments: [StyledSegment]
    let isWrapped: Bool
    var isTableRow: Bool = false
    /// Set by the parser when the original terminal character is a known
    /// conversation marker (❯ for user, ⏺ for assistant) with the expected
    /// ANSI style. Spinner characters that happen to match are excluded.
    var markerRole: MarkerRole = .none
}

/// A contiguous run of text sharing the same style.
struct StyledSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: SegmentStyle

    /// Content equality. The `id` is regenerated on every parser extraction,
    /// so it must not participate — equal text + style means the segment is
    /// unchanged and its rendered view can be reused.
    static func == (lhs: StyledSegment, rhs: StyledSegment) -> Bool {
        lhs.text == rhs.text && lhs.style == rhs.style
    }
}

/// Visual style attributes for a terminal text segment.
struct SegmentStyle: Equatable {
    var fgColor: ANSIColor = .defaultFg
    var bgColor: ANSIColor = .defaultBg
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isDim: Bool = false
}

/// Terminal color representation.
enum ANSIColor: Equatable, Hashable {
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
    case defaultFg
    case defaultBg
}
