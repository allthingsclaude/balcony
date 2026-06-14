import SwiftUI
import BalconyShared

/// Native renderer for the structured ``TranscriptEvent`` stream parsed from the
/// session JSONL — the reliable alternative to the PTY screen scrape.
///
/// This is the iOS half of the JSONL-source-of-truth spike: drop it in alongside
/// `ConversationView` to compare side-by-side. It renders real message bubbles,
/// markdown prose, tool cards, and collapsed results — no spinner ghosts, no
/// code-block guessing, because the input is already structured.
struct TranscriptMessageList: View {
    let events: [TranscriptEvent]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BalconyTheme.spacingMD) {
                    ForEach(visibleEvents) { event in
                        TranscriptEventView(event: event)
                            .id(event.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, BalconyTheme.spacingMD)
                .padding(.vertical, BalconyTheme.spacingLG)
            }
            .background(BalconyTheme.background.ignoresSafeArea())
            .onChange(of: events.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// Sub-agent turns are hidden from the main transcript (matches the TUI).
    private var visibleEvents: [TranscriptEvent] {
        events.filter { !$0.isSidechain }
    }
}

// MARK: - Event

/// Renders one transcript turn (user/assistant) and its content blocks.
/// Reused by the hybrid `ConversationView` to render settled history.
struct TranscriptEventView: View {
    let event: TranscriptEvent

    var body: some View {
        VStack(alignment: .leading, spacing: BalconyTheme.spacingSM) {
            ForEach(Array(event.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RoleContainer(role: event.role))
    }

    @ViewBuilder
    private func blockView(_ block: TranscriptBlock) -> some View {
        switch block {
        case .text(let text):
            MarkdownText(text)
                .font(BalconyTheme.bodyFont(15))
                .foregroundStyle(BalconyTheme.textPrimary)
        case .thinking(let text):
            MarkdownText(text)
                .font(BalconyTheme.bodyFont(14).italic())
                .foregroundStyle(BalconyTheme.textSecondary)
        case .toolUse(_, let name, let input):
            ToolUseRow(name: name, input: input)
        case .toolResult(_, let text, let isError):
            ToolResultRow(text: text, isError: isError)
        case .image(let altText):
            Label(altText, systemImage: "photo")
                .font(BalconyTheme.bodyFont(13))
                .foregroundStyle(BalconyTheme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(BalconyTheme.surfaceSecondary, in: Capsule())
        }
    }
}

/// User turns get the accent rail + tinted surface; assistant turns are plain.
private struct RoleContainer: ViewModifier {
    let role: TranscriptEvent.Role

    func body(content: Content) -> some View {
        switch role {
        case .user:
            content
                .padding(BalconyTheme.spacingMD)
                .background(BalconyTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: BalconyTheme.radiusMD))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BalconyTheme.accent)
                        .frame(width: 3)
                }
        case .assistant:
            content
        }
    }
}

// MARK: - Working Indicator

/// Immediate "Claude is working" feedback shown while a reply is in flight and
/// before the live PTY tail has any text.
struct WorkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(BalconyTheme.accent)
                .frame(width: 7, height: 7)
                .opacity(animating ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animating)
            Text("Working…")
                .font(BalconyTheme.bodyFont(14))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}

// MARK: - Tool rows

private struct ToolUseRow: View {
    let name: String
    let input: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(BalconyTheme.monoFont(13).weight(.semibold))
                .foregroundStyle(BalconyTheme.accent)
            if !input.isEmpty {
                Text(input)
                    .font(BalconyTheme.monoFont(13))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BalconyTheme.surface, in: RoundedRectangle(cornerRadius: BalconyTheme.radiusSM))
        .overlay(
            RoundedRectangle(cornerRadius: BalconyTheme.radiusSM)
                .strokeBorder(BalconyTheme.separator, lineWidth: 1)
        )
    }
}

/// Tool results are collapsed by default — they're usually long and noisy.
private struct ToolResultRow: View {
    let text: String
    let isError: Bool
    @State private var expanded = false

    private var firstLine: String {
        text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isError ? "xmark.octagon.fill" : "arrow.turn.down.right")
                        .font(.system(size: 11))
                    Text(expanded ? firstLine : firstLine)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .font(BalconyTheme.monoFont(12))
                .foregroundStyle(isError ? BalconyTheme.statusRed : BalconyTheme.textSecondary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(BalconyTheme.monoFont(12))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(BalconyTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: BalconyTheme.radiusSM))
    }
}

// MARK: - Markdown

/// Lightweight inline-markdown text with a plain-string fallback.
private struct MarkdownText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    TranscriptMessageList(events: [
        TranscriptEvent(id: "1", role: .user, blocks: [.text("yooo")]),
        TranscriptEvent(id: "2", role: .assistant, blocks: [
            .thinking("They want a status check. Keep it short."),
            .text("yo! what's up?\n\nWant me to dig into anything in Balcony? I see you've got `HookEventHandler.swift` open."),
        ]),
        TranscriptEvent(id: "3", role: .user, blocks: [.text("no thanks")]),
        TranscriptEvent(id: "4", role: .assistant, blocks: [
            .text("Cool, no worries. I'm here when you need me. 🍺"),
            .toolUse(id: "t1", name: "Read", input: "BalconyiOS/Sources/Views/Terminal/HeadlessTerminalParser.swift"),
            .toolResult(toolUseID: "t1", text: "1\timport Foundation\n2\timport SwiftTerm\n…", isError: false),
        ]),
    ])
}
#endif
