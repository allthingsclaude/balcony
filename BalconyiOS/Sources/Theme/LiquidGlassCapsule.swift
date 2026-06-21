import SwiftUI

/// Applies iOS 26 Liquid Glass in a capsule shape.
///
/// Use for fully-rounded pill controls (round buttons, badges) whose roundness
/// should always track the height. For containers that must keep a *constant*
/// corner radius as they grow — like the multi-line input bar — use
/// ``LiquidGlassRoundedRect`` instead.
struct LiquidGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .capsule)
    }
}

/// Applies iOS 26 Liquid Glass in a fixed-radius rounded rectangle.
///
/// Unlike ``LiquidGlassCapsule``, the corner radius stays constant in points as
/// the container grows. When the container's height equals `2 * cornerRadius`
/// the rounded ends form perfect semicircles, so it reads as a fully rounded
/// pill; taller containers keep the same corner radius and read as a rounded
/// rectangle. Used by the message input bar so it looks like a pill on a single
/// line and a rounded rectangle once it wraps.
struct LiquidGlassRoundedRect: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
