import SwiftUI

struct EscButton: View {
    let onTap: () -> Void
    var onDoubleTap: (() -> Void)?

    /// Timestamp of the last tap for double-tap detection.
    @State private var lastTapTime: Date = .distantPast

    /// Double-tap window in seconds.
    private let doubleTapInterval: TimeInterval = 0.35

    var body: some View {
        Button {
            BalconyTheme.hapticLight()
            let now = Date()
            let elapsed = now.timeIntervalSince(lastTapTime)

            if elapsed < doubleTapInterval, let onDoubleTap {
                // Double-tap detected — reset timer and fire callback
                lastTapTime = .distantPast
                BalconyTheme.hapticMedium()
                onDoubleTap()
            } else {
                // First tap — record time and fire single-tap
                lastTapTime = now
                onTap()
            }
        } label: {
            Text("esc")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(BalconyTheme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(BalconyTheme.textSecondary.opacity(0)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Escape")
    }
}
