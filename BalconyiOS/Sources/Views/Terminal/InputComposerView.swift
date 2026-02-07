import SwiftUI

struct InputComposerView: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Quick actions
            HStack(spacing: 4) {
                QuickActionButton(title: "Approve", color: .green) { onSend() }
                QuickActionButton(title: "Deny", color: .red) { onSend() }
            }

            // Text input
            TextField("Send input...", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSend() }

            // Send button
            Button {
                onSend()
            } label: {
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
