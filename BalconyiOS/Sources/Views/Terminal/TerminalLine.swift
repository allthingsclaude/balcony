import Foundation

/// A single line of parsed terminal output with styled segments.
struct TerminalLine: Identifiable {
    let id: Int
    let segments: [StyledSegment]
    let isWrapped: Bool
}

/// A contiguous run of text sharing the same style.
struct StyledSegment: Identifiable {
    let id = UUID()
    let text: String
    let style: SegmentStyle
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
enum ANSIColor: Equatable {
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
    case defaultFg
    case defaultBg
}
