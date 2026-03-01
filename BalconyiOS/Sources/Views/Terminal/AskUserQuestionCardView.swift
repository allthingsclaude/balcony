import SwiftUI
import BalconyShared

/// Native iOS card for AskUserQuestion prompts from Claude Code.
/// Wizard-style: one question at a time with navigation.
struct AskUserQuestionCardView: View {
    let payload: AskUserQuestionPayload
    let onComplete: ([String: String]) -> Void
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var otherText = ""
    @State private var showOtherField = false

    private var questions: [AskUserQuestionPayload.Question] {
        payload.questions
    }

    private var currentQuestion: AskUserQuestionPayload.Question {
        questions[currentIndex]
    }

    private var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            Divider()
                .background(BalconyTheme.separator)

            // Question text
            questionContent

            Divider()
                .background(BalconyTheme.separator)

            // Options
            optionsList

            // "Other" text input
            if showOtherField {
                otherInput
            }
        }
        .background {
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
        }
        .clipShape(RoundedRectangle(cornerRadius: BalconyTheme.radiusMD))
        .padding(.horizontal, BalconyTheme.spacingLG)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BalconyTheme.accent)

            if questions.count > 1 {
                Text("Step \(currentIndex + 1) of \(questions.count)")
                    .font(BalconyTheme.bodyFont(14))
                    .fontWeight(.semibold)
                    .foregroundStyle(BalconyTheme.textPrimary)
            }

            if !currentQuestion.header.isEmpty {
                Text(currentQuestion.header)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(BalconyTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(BalconyTheme.accentSubtle, in: Capsule())
            }

            Spacer()

            Button {
                BalconyTheme.hapticLight()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(BalconyTheme.textSecondary.opacity(0.1), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Question

    private var questionContent: some View {
        Text(currentQuestion.question)
            .font(BalconyTheme.bodyFont(14))
            .fontWeight(.medium)
            .foregroundStyle(BalconyTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    // MARK: - Options

    private var optionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(currentQuestion.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        BalconyTheme.hapticMedium()
                        selectOption(option.label)
                    } label: {
                        optionRow(option, index: index)
                    }
                    .buttonStyle(.plain)
                }

                // "Other" option
                Button {
                    BalconyTheme.hapticMedium()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showOtherField = true
                    }
                } label: {
                    otherRow
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 280)
    }

    private func optionRow(_ option: AskUserQuestionPayload.Question.Option, index: Int) -> some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(BalconyTheme.bodyFont(14))
                    .fontWeight(.medium)
                    .foregroundStyle(BalconyTheme.textPrimary)

                if let description = option.description, !description.isEmpty {
                    Text(description)
                        .font(BalconyTheme.bodyFont(12))
                        .foregroundStyle(BalconyTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var otherRow: some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            Text("Other")
                .font(BalconyTheme.bodyFont(14))
                .fontWeight(.medium)
                .foregroundStyle(BalconyTheme.textSecondary)
                .italic()

            Spacer()

            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Other Input

    private var otherInput: some View {
        VStack(spacing: 8) {
            Divider()
                .background(BalconyTheme.separator)

            HStack(spacing: 8) {
                TextField("Type your answer...", text: $otherText)
                    .textFieldStyle(.plain)
                    .font(BalconyTheme.bodyFont(14))
                    .onSubmit { submitOther() }

                Button {
                    submitOther()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(otherText.isEmpty ? BalconyTheme.textSecondary.opacity(0.3) : BalconyTheme.accent)
                }
                .disabled(otherText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func selectOption(_ label: String) {
        answers[currentQuestion.question] = label
        showOtherField = false
        otherText = ""
        advanceOrComplete()
    }

    private func submitOther() {
        guard !otherText.isEmpty else { return }
        answers[currentQuestion.question] = otherText
        showOtherField = false
        otherText = ""
        advanceOrComplete()
    }

    private func advanceOrComplete() {
        if isLastQuestion {
            BalconyTheme.hapticSuccess()
            onComplete(answers)
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                currentIndex += 1
            }
        }
    }
}
