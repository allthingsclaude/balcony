import SwiftUI

struct InputComposerView: View {
    @Binding var text: String
    var showQuickActions: Bool
    var onApprove: () -> Void
    var onDeny: () -> Void
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Quick actions — only shown when session is waiting for input
            if showQuickActions {
                HStack(spacing: 4) {
                    QuickActionButton(title: "Approve", color: .green, action: onApprove)
                    QuickActionButton(title: "Deny", color: .red, action: onDeny)
                }
            }

            // Text input
            TextField("Send input...", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSend() }

            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - QuickActionButton

private struct QuickActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(color)
    }
}
