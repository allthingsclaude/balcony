import Foundation

/// Tracks the state of the multi-slide onboarding flow.
@MainActor
@Observable
final class OnboardingFlowModel {

    // MARK: - Slide Definitions

    enum Slide: Int, CaseIterable {
        case welcome
        case setup
        case floatingPanels
        case quickFocus
        case voiceInput
        case iosCompanion
        case allSet
    }

    // MARK: - Setup Sub-Step Status

    enum SetupStep: Int, CaseIterable {
        case balconyDir
        case hookHandler
        case installCLI
        case patchHooks
        case aliasSetup
    }

    enum StepStatus: Equatable {
        case pending
        case inProgress
        case completed
        case skipped
        case failed(String)
    }

    // MARK: - State

    var currentSlide: Slide = .welcome
    var slideDirection: SlideDirection = .forward

    /// Status of each technical setup sub-step.
    var setupStepStatuses: [SetupStep: StepStatus] = [:]
    var cliNeedsAdmin: Bool = false
    var manualCLICommand: String?
    var errorMessage: String?
    var isSetupRunning: Bool = false

    /// Callback fired when onboarding finishes.
    var onComplete: (() -> Void)?

    // MARK: - Navigation Direction

    enum SlideDirection {
        case forward, backward
    }

    // MARK: - Navigation

    var slideCount: Int { Slide.allCases.count }
    var isFirstSlide: Bool { currentSlide == .welcome }
    var isLastSlide: Bool { currentSlide == .allSet }

    var canGoBack: Bool {
        currentSlide.rawValue > 0
    }

    var canGoNext: Bool {
        if isLastSlide { return false }
        if currentSlide == .setup { return isSetupComplete }
        return true
    }

    func goNext() {
        guard canGoNext else { return }
        guard let next = Slide(rawValue: currentSlide.rawValue + 1) else { return }
        slideDirection = .forward
        currentSlide = next
    }

    func goBack() {
        guard canGoBack else { return }
        guard let prev = Slide(rawValue: currentSlide.rawValue - 1) else { return }
        slideDirection = .backward
        currentSlide = prev
    }

    // MARK: - Setup Helpers

    /// Whether all 5 setup sub-steps are completed or skipped.
    var isSetupComplete: Bool {
        SetupStep.allCases.allSatisfy { step in
            switch setupStatus(for: step) {
            case .completed, .skipped: return true
            default: return false
            }
        }
    }

    func setupStatus(for step: SetupStep) -> StepStatus {
        setupStepStatuses[step] ?? .pending
    }

    func setupTitle(for step: SetupStep) -> String {
        switch step {
        case .balconyDir: return "Create Balcony directory"
        case .hookHandler: return "Install hook handler"
        case .installCLI: return "Install CLI"
        case .patchHooks: return "Configure Claude Code hooks"
        case .aliasSetup: return "Set up shell alias"
        }
    }

    func setupSubtitle(for step: SetupStep) -> String {
        switch step {
        case .balconyDir: return "Creates ~/.balcony/ for runtime data"
        case .hookHandler: return "Enables Claude Code event notifications"
        case .installCLI: return "Installs balcony command to /usr/local/bin"
        case .patchHooks: return "Adds Balcony hooks to ~/.claude/settings.json"
        case .aliasSetup: return "Aliases claude → balcony in your shell"
        }
    }

    // MARK: - Reset

    func reset() {
        currentSlide = .welcome
        slideDirection = .forward
        setupStepStatuses = [:]
        cliNeedsAdmin = false
        manualCLICommand = nil
        errorMessage = nil
        isSetupRunning = false
    }
}
