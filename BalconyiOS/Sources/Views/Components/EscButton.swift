import SwiftUI

struct EscButton: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            BalconyTheme.hapticLight()
            onTap()
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
