import SwiftUI

/// Shared brand palette for onboarding views, matching the terracotta PanelTheme aesthetic.
enum OnboardingTheme {
    static let brand = Color(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0)
    static let brandDark = Color(red: 0xB8/255.0, green: 0x5A/255.0, blue: 0x3A/255.0)
    static let brandLight = Color(red: 0xF0/255.0, green: 0xC4/255.0, blue: 0xAE/255.0)
    static let brandLighter = Color(red: 0xF5/255.0, green: 0xD9/255.0, blue: 0xCB/255.0)

    static let surface = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.07)
                : NSColor(white: 0.0, alpha: 0.04)
        }
    ))

    static let divider = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.08)
                : NSColor(white: 0.0, alpha: 0.06)
        }
    ))
}
