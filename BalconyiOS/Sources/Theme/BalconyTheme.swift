import SwiftUI
import UIKit

// MARK: - Balcony Theme

/// Central theme definition for the Balcony iOS app.
/// Matches the warm, humanistic design language of the Claude iOS app.
enum BalconyTheme {

    // MARK: - Colors

    /// Cream/beige main screen background
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.102, green: 0.098, blue: 0.082, alpha: 1) // #1A1915
            : UIColor(red: 0.980, green: 0.976, blue: 0.961, alpha: 1) // #FAF9F5
    })

    /// Cards, input fields
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.145, green: 0.141, blue: 0.125, alpha: 1) // #252420
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)       // #FFFFFF
    })

    /// Sidebar background — slightly darker than main background
    static let sidebarBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.082, green: 0.078, blue: 0.065, alpha: 1)  // #151410
            : UIColor(red: 0.935, green: 0.930, blue: 0.910, alpha: 1) // #EFEDE8
    })

    /// Grouped list backgrounds, user message bubbles
    static let surfaceSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.122, green: 0.118, blue: 0.102, alpha: 1) // #1F1E1A
            : UIColor(red: 0.957, green: 0.953, blue: 0.933, alpha: 1) // #F4F3EE
    })

    /// Terracotta orange accent
    static let accent = Color(uiColor: UIColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1)) // #D97757

    /// Accent-tinted subtle background (15% opacity)
    static let accentSubtle = Color(uiColor: UIColor { traits in
        UIColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 0.15) // #D97757 @ 15%
    })

    /// Primary text
    static let textPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.961, green: 0.957, blue: 0.937, alpha: 1) // #F5F4EF
            : UIColor(red: 0.102, green: 0.094, blue: 0.086, alpha: 1) // #1A1816
    })

    /// Secondary/caption text
    static let textSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.541, green: 0.529, blue: 0.502, alpha: 1) // #8A8780
            : UIColor(red: 0.541, green: 0.522, blue: 0.478, alpha: 1) // #8A857A
    })

    /// Dividers, borders
    static let separator = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.200, green: 0.188, blue: 0.157, alpha: 1) // #333028
            : UIColor(red: 0.910, green: 0.902, blue: 0.863, alpha: 1) // #E8E6DC
    })

    /// Active/live status
    static let statusGreen = Color(uiColor: UIColor(red: 0.471, green: 0.549, blue: 0.365, alpha: 1)) // #788C5D

    /// Idle status
    static let statusYellow = Color(uiColor: UIColor(red: 0.769, green: 0.635, blue: 0.298, alpha: 1)) // #C4A24C

    /// Error status
    static let statusRed = Color(uiColor: UIColor(red: 0.769, green: 0.294, blue: 0.247, alpha: 1)) // #C44B3F

    // MARK: - Fonts

    /// Rounded UI heading font
    static func headingFont(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Rounded UI body font
    static func bodyFont(_ size: CGFloat = 15) -> Font {
        .system(size: size, design: .rounded)
    }

    /// Monospaced font for terminal content
    static func monoFont(_ size: CGFloat = 13) -> Font {
        .system(size: size, design: .monospaced)
    }

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // MARK: - Gradients

    /// 3-stop bottom fade gradient matching ConversationView pattern.
    static func bottomFadeGradient(for color: Color = background) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: color.opacity(0), location: 0),
                .init(color: color.opacity(0.8), location: 0.5),
                .init(color: color, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Corner Radius

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusPill: CGFloat = 24

    // MARK: - Haptics

    static func hapticLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func hapticMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func hapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func hapticError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - Section Headers

    @ViewBuilder
    static func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(textSecondary)
    }
}

// MARK: - Button Styles

/// Press-scale button style for interactive cards.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
