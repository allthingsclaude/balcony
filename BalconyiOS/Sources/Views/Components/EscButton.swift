import SwiftUI

/// Interrupt button: instant ESC on tap (no double-tap latency), rewind picker
/// on long-press. Hit target is 44pt per HIG.
struct EscButton: View {
    let onTap: () -> Void
    var onLongPress: (() -> Void)?

    var body: some View {
        Text("esc")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(BalconyTheme.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                BalconyTheme.hapticMedium()
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                BalconyTheme.hapticMedium()
                onLongPress?()
            }
            .accessibilityLabel("Escape")
            .accessibilityHint("Interrupts Claude. Long-press to rewind.")
            .accessibilityAddTraits(.isButton)
    }
}
