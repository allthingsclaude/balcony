import SwiftUI

/// Applies iOS 26 Liquid Glass in a capsule shape.
struct LiquidGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .capsule)
    }
}
