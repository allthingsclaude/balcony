import SwiftUI

/// Maps `ANSIColor` values to SwiftUI `Color`.
enum ANSIColorMapper {
    /// Convert an ANSIColor to a SwiftUI Color.
    static func color(for ansi: ANSIColor) -> Color {
        switch ansi {
        case .defaultFg:
            return BalconyTheme.textPrimary
        case .defaultBg:
            return BalconyTheme.background
        case .rgb(let r, let g, let b):
            return Color(
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0
            )
        case .palette(let code):
            return paletteColor(code)
        }
    }

    // MARK: - Palette

    private static func paletteColor(_ code: UInt8) -> Color {
        if code < 16 {
            return standardColor(code)
        } else if code < 232 {
            return cubeColor(code)
        } else {
            return grayscaleColor(code)
        }
    }

    /// Standard 16 ANSI colors (0-15).
    private static func standardColor(_ code: UInt8) -> Color {
        switch code {
        case 0:  return Color(red: 0.0, green: 0.0, blue: 0.0)           // Black
        case 1:  return Color(red: 0.67, green: 0.0, blue: 0.0)          // Red
        case 2:  return Color(red: 0.0, green: 0.67, blue: 0.0)          // Green
        case 3:  return Color(red: 0.67, green: 0.67, blue: 0.0)         // Yellow
        case 4:  return Color(red: 0.0, green: 0.0, blue: 0.67)          // Blue
        case 5:  return Color(red: 0.67, green: 0.0, blue: 0.67)         // Magenta
        case 6:  return Color(red: 0.0, green: 0.67, blue: 0.67)         // Cyan
        case 7:  return BalconyTheme.textSecondary                            // White (warm adaptive)
        case 8:  return Color(red: 0.33, green: 0.33, blue: 0.33)        // Bright Black
        case 9:  return Color(red: 1.0, green: 0.33, blue: 0.33)         // Bright Red
        case 10: return Color(red: 0.33, green: 1.0, blue: 0.33)         // Bright Green
        case 11: return Color(red: 1.0, green: 1.0, blue: 0.33)          // Bright Yellow
        case 12: return Color(red: 0.33, green: 0.33, blue: 1.0)         // Bright Blue
        case 13: return Color(red: 1.0, green: 0.33, blue: 1.0)          // Bright Magenta
        case 14: return Color(red: 0.33, green: 1.0, blue: 1.0)          // Bright Cyan
        case 15: return BalconyTheme.textPrimary                             // Bright White (warm adaptive)
        default: return .primary
        }
    }

    /// 6x6x6 color cube (codes 16-231).
    private static func cubeColor(_ code: UInt8) -> Color {
        let index = Int(code) - 16
        let b = index % 6
        let g = (index / 6) % 6
        let r = index / 36
        return Color(
            red: r == 0 ? 0 : (Double(r) * 40.0 + 55.0) / 255.0,
            green: g == 0 ? 0 : (Double(g) * 40.0 + 55.0) / 255.0,
            blue: b == 0 ? 0 : (Double(b) * 40.0 + 55.0) / 255.0
        )
    }

    /// 24-step grayscale ramp (codes 232-255).
    private static func grayscaleColor(_ code: UInt8) -> Color {
        let level = Double(Int(code) - 232) * 10.0 + 8.0
        let value = level / 255.0
        return Color(red: value, green: value, blue: value)
    }
}
