import SwiftUI
import BalconyShared

struct StatusBadge: View {
    let status: SessionStatus
    var compact: Bool = false

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                // Pulse ring for active status
                if status == .active && !reduceMotion {
                    Circle()
                        .stroke(color.opacity(pulseOpacity), lineWidth: 1.5)
                        .frame(width: 8 * pulseScale, height: 8 * pulseScale)
                        .onAppear {
                            withAnimation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                            ) {
                                pulseScale = 2.5
                                pulseOpacity = 0
                            }
                        }
                }
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 20, height: 20)

            if !compact {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, compact ? 0 : 8)
        .accessibilityLabel(label)
    }

    private var color: Color {
        switch status {
        case .active: return BalconyTheme.accent
        case .idle: return BalconyTheme.statusYellow
        case .completed: return BalconyTheme.textSecondary
        case .error: return BalconyTheme.statusRed
        }
    }

    private var label: String {
        switch status {
        case .active: return "Active"
        case .idle: return "Idle"
        case .completed: return "Done"
        case .error: return "Error"
        }
    }
}
