import Foundation

/// Tracks the state of the first-launch setup wizard.
@MainActor
@Observable
final class SetupFlowModel {

    // MARK: - Step Definitions

    enum Step: Int, CaseIterable {
        case balconyDir
        case hookHandler
        case installCLI
        case patchHooks
        case aliasSetup
        case complete
    }

    enum StepStatus: Equatable {
        case pending
        case inProgress
        case completed
        case skipped
        case failed(String)
    }

    // MARK: - State

    var currentStep: Step = .balconyDir
    var stepStatuses: [Step: StepStatus] = [:]
    var wantsAlias: Bool = true
    var cliNeedsAdmin: Bool = false
    var manualCLICommand: String?
    var errorMessage: String?

    /// Callback fired when the wizard finishes (user taps "Get Started").
    var onComplete: (() -> Void)?

    /// Reset all state so the wizard can be re-run.
    func reset() {
        currentStep = .balconyDir
        stepStatuses = [:]
        wantsAlias = true
        cliNeedsAdmin = false
        manualCLICommand = nil
        errorMessage = nil
    }

    // MARK: - Computed

    /// Steps that the user sees (excludes .complete which is the summary screen).
    static let visibleSteps: [Step] = [.balconyDir, .hookHandler, .installCLI, .patchHooks, .aliasSetup]

    func status(for step: Step) -> StepStatus {
        stepStatuses[step] ?? .pending
    }

    func title(for step: Step) -> String {
        switch step {
        case .balconyDir: return "Create Balcony directory"
        case .hookHandler: return "Install hook handler"
        case .installCLI: return "Install CLI"
        case .patchHooks: return "Configure Claude Code hooks"
        case .aliasSetup: return "Set up shell alias"
        case .complete: return "Setup complete"
        }
    }

    func subtitle(for step: Step) -> String {
        switch step {
        case .balconyDir: return "Creates ~/.balcony/ for runtime data"
        case .hookHandler: return "Enables Claude Code event notifications"
        case .installCLI: return "Installs balcony command to /usr/local/bin"
        case .patchHooks: return "Adds Balcony hooks to ~/.claude/settings.json"
        case .aliasSetup: return "Aliases claude → balcony in your shell"
        case .complete: return ""
        }
    }

    /// The SF Symbol name for a step's status indicator.
    func statusIcon(for step: Step) -> String {
        switch status(for: step) {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    /// Whether we're on the final summary screen.
    var isOnSummary: Bool {
        currentStep == .complete
    }

    /// All actionable steps are done (completed, skipped, or failed).
    var allStepsDone: Bool {
        SetupFlowModel.visibleSteps.allSatisfy { step in
            switch status(for: step) {
            case .completed, .skipped: return true
            default: return false
            }
        }
    }
}
