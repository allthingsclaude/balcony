import SwiftUI

/// Interrupt button: instant ESC on tap (no double-tap latency), rewind picker
/// on double-tap or long-press. Hit target is 44pt per HIG.
///
/// Double-tap is detected manually (rather than `onTapGesture(count: 2)`) so the
/// single tap stays instant — the first tap fires the interrupt immediately and
/// a quick second tap opens rewind, mirroring the CLI's double-ESC shortcut.
struct EscButton: View {
    let onTap: () -> Void
    var onDoubleTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    /// Max gap between taps to count as a double-tap.
    private static let doubleTapWindow: TimeInterval = 0.35
    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        Text("esc")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(BalconyTheme.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                BalconyTheme.hapticMedium()
                let now = Date()
                if now.timeIntervalSince(lastTapTime) < Self.doubleTapWindow {
                    // Second quick tap → rewind. The first tap already interrupted.
                    lastTapTime = .distantPast
                    onDoubleTap?()
                } else {
                    lastTapTime = now
                    onTap()
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                BalconyTheme.hapticMedium()
                onLongPress?()
            }
            .accessibilityLabel("Escape")
            .accessibilityHint("Interrupts Claude. Double-tap or long-press to rewind.")
            .accessibilityAddTraits(.isButton)
    }
}
