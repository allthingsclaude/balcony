import SwiftUI

/// Shared chrome for the drag-to-dismiss pickers (/model, /resume, /rewind):
/// titled drag handle, divider, content in a glass card. Owns the
/// drag-to-dismiss gesture so the three pickers can't drift apart.
struct PickerScaffold<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            Divider()
                .background(BalconyTheme.separator)

            content()
        }
        .background {
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
        }
        .clipShape(RoundedRectangle(cornerRadius: BalconyTheme.radiusMD))
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 160 {
                        BalconyTheme.hapticLight()
                        onDismiss()
                    } else {
                        withAnimation(BalconyTheme.springSnappy) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .accessibilityAction(.escape) { onDismiss() }
    }

    private var dragHandle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(BalconyTheme.textSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text(title)
                .font(BalconyTheme.bodyFont(13))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, BalconyTheme.spacingSM)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Swipe down to dismiss.")
    }
}

/// Shared "no results" body for picker and menu lists.
struct PickerEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: BalconyTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(BalconyTheme.textSecondary)
                .padding(.top, BalconyTheme.spacingXL)

            Text(message)
                .font(BalconyTheme.bodyFont(15))
                .foregroundStyle(BalconyTheme.textSecondary)
                .padding(.bottom, BalconyTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
    }
}
