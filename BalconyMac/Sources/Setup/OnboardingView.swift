import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Onboarding View

/// Multi-slide onboarding flow combining setup and feature walkthrough.
struct OnboardingView: View {
    let model: OnboardingFlowModel
    let manager: SetupManager

    var body: some View {
        VStack(spacing: 0) {
            // Slide content
            slideContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            OnboardingTheme.divider
                .frame(height: 1)

            // Navigation bar
            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 640, height: 480)
    }

    // MARK: - Slide Content

    @ViewBuilder
    private var slideContent: some View {
        Group {
            switch model.currentSlide {
            case .welcome:
                welcomeSlide
            case .setup:
                setupSlide
            case .floatingPanels:
                floatingPanelsSlide
            case .quickFocus:
                quickFocusSlide
            case .voiceInput:
                voiceInputSlide
            case .iosCompanion:
                iosCompanionSlide
            case .allSet:
                allSetSlide
            }
        }
        .id(model.currentSlide)
        .transition(.asymmetric(
            insertion: .move(edge: model.slideDirection == .forward ? .trailing : .leading),
            removal: .move(edge: model.slideDirection == .forward ? .leading : .trailing)
        ))
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    model.goBack()
                }
            }
            .opacity(model.isFirstSlide ? 0 : 1)
            .disabled(model.isFirstSlide)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(OnboardingFlowModel.Slide.allCases, id: \.rawValue) { slide in
                    Circle()
                        .fill(
                            slide == model.currentSlide
                                ? OnboardingTheme.brand
                                : OnboardingTheme.brand.opacity(0.25)
                        )
                        .frame(
                            width: slide == model.currentSlide ? 10 : 8,
                            height: slide == model.currentSlide ? 10 : 8
                        )
                        .animation(.easeInOut(duration: 0.2), value: model.currentSlide)
                }
            }

            Spacer()

            // Next / Get Started
            if model.isLastSlide {
                Button("Get Started") {
                    manager.markComplete()
                    model.onComplete?()
                }
                .buttonStyle(.borderedProminent)
                .tint(OnboardingTheme.brand)
            } else if model.isFirstSlide {
                Button("Get Started") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        model.slideDirection = .forward
                        model.goNext()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OnboardingTheme.brand)
            } else {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        model.goNext()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OnboardingTheme.brand)
                .disabled(!model.canGoNext)
            }
        }
    }

    // MARK: - Slide 1: Welcome

    private var welcomeSlide: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Welcome to Balcony")
                .font(.system(size: 28, weight: .semibold))

            Text("Your companion for Claude Code.\nMonitor sessions, respond to prompts,\nand stay connected from anywhere.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Slide 2: Setup

    private var setupSlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setting things up")
                .font(.title2.weight(.semibold))

            Text("Balcony needs a few things configured to work with Claude Code.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Setup checklist
            VStack(alignment: .leading, spacing: 2) {
                ForEach(OnboardingFlowModel.SetupStep.allCases, id: \.rawValue) { step in
                    setupStepRow(for: step)
                }
            }
            .padding(.top, 4)

            // Interactive section for current step
            setupInteractiveContent

            if let error = model.errorMessage {
                errorBanner(error)
            }

            Spacer()
        }
        .padding(32)
        .onAppear {
            runAutoSetupSteps()
        }
    }

    private func setupStepRow(for step: OnboardingFlowModel.SetupStep) -> some View {
        let status = model.setupStatus(for: step)
        let isActive = isCurrentSetupStep(step)

        return HStack(spacing: 10) {
            setupStatusIcon(for: status)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.setupTitle(for: step))
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)

                if isActive {
                    Text(model.setupSubtitle(for: step))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            isActive ? OnboardingTheme.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    @ViewBuilder
    private func setupStatusIcon(for status: OnboardingFlowModel.StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }

    /// Whether a setup step is the one currently needing attention.
    private func isCurrentSetupStep(_ step: OnboardingFlowModel.SetupStep) -> Bool {
        // The current active step is the first non-completed/non-skipped step
        for s in OnboardingFlowModel.SetupStep.allCases {
            switch model.setupStatus(for: s) {
            case .completed, .skipped: continue
            default: return s == step
            }
        }
        return false
    }

    /// Interactive controls for the current setup sub-step needing user action.
    @ViewBuilder
    private var setupInteractiveContent: some View {
        let activeStep = OnboardingFlowModel.SetupStep.allCases.first { step in
            switch model.setupStatus(for: step) {
            case .completed, .skipped: return false
            default: return true
            }
        }

        if let step = activeStep {
            switch step {
            case .installCLI:
                cliInteractiveContent
            case .patchHooks:
                hooksInteractiveContent
            case .aliasSetup:
                aliasInteractiveContent
            default:
                EmptyView()
            }
        }
    }

    // MARK: - CLI Interactive

    @ViewBuilder
    private var cliInteractiveContent: some View {
        let status = model.setupStatus(for: .installCLI)

        if case .pending = status, !model.cliNeedsAdmin {
            // Show nothing — auto-step will handle or transition to needsAdmin
        } else if model.cliNeedsAdmin {
            VStack(alignment: .leading, spacing: 8) {
                Text("Writing to /usr/local/bin requires administrator access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Install with Admin") {
                        installCLIWithAdmin()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OnboardingTheme.brand)

                    Button("Skip") {
                        model.setupStepStatuses[.installCLI] = .skipped
                        continueAutoSetup(from: .patchHooks)
                    }
                }

                if let cmd = model.manualCLICommand {
                    Text("Or run manually:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(cmd)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(OnboardingTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Hooks Interactive

    @ViewBuilder
    private var hooksInteractiveContent: some View {
        let status = model.setupStatus(for: .patchHooks)

        if case .pending = status {
            HStack(spacing: 12) {
                Button("Patch Settings") {
                    performPatchHooks()
                }
                .buttonStyle(.borderedProminent)
                .tint(OnboardingTheme.brand)

                Button("Skip") {
                    model.setupStepStatuses[.patchHooks] = .skipped
                    continueAutoSetup(from: .aliasSetup)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Alias Interactive

    @ViewBuilder
    private var aliasInteractiveContent: some View {
        let status = model.setupStatus(for: .aliasSetup)

        if case .pending = status {
            VStack(alignment: .leading, spacing: 8) {
                if let profilePath = manager.shellProfilePath {
                    Text("Will add `alias claude=balcony` to \(profilePath)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Add Alias") {
                        performAliasInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OnboardingTheme.brand)

                    Button("Skip") {
                        model.setupStepStatuses[.aliasSetup] = .skipped
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Slide 3: Floating Panels

    private var floatingPanelsSlide: some View {
        educationSlide(
            icon: "macwindow.on.rectangle",
            title: "Floating Panels",
            description: "When Claude needs your approval or finishes a task, Balcony shows floating panels right on your screen — no need to switch apps.",
            detail: "Permission requests show the tool, command, and risk level. Tap Allow, Deny, or Always to respond instantly."
        )
    }

    // MARK: - Slide 4: Quick Focus

    private var quickFocusSlide: some View {
        VStack(spacing: 24) {
            Spacer()

            // Keyboard shortcut visual
            HStack(spacing: 12) {
                keyCapView(symbol: "command")
                keyCapView(symbol: "command")
            }

            Text("Quick Focus")
                .font(.system(size: 24, weight: .semibold))

            Text("Double-tap the **Command** key to instantly\nfocus the frontmost Balcony panel.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("Works from any app — no need to click or switch windows.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Slide 5: Voice Input

    private var voiceInputSlide: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(OnboardingTheme.brand.opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(OnboardingTheme.brand)
            }

            Text("Voice Input")
                .font(.system(size: 24, weight: .semibold))

            Text("**Hold** the Command key after double-tapping\nto dictate your response. Release to send.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack(spacing: 16) {
                shortcutStep(number: "1", text: "Double-tap ⌘")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                shortcutStep(number: "2", text: "Keep holding")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                shortcutStep(number: "3", text: "Release to send")
            }
            .font(.callout)
            .padding(.top, 4)

            Text("You can enable this in Settings → Notifications.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Slide 6: iOS Companion

    private var iosCompanionSlide: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "iphone")
                .font(.system(size: 40))
                .foregroundStyle(OnboardingTheme.brand)

            Text("iOS Companion")
                .font(.system(size: 24, weight: .semibold))

            Text("Download Balcony on your iPhone to monitor sessions,\nrespond to prompts, and get notified — even away from your desk.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            if let qrImage = generateQRCode(from: "https://balcony.app/ios") {
                Image(nsImage: qrImage)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.primary)
            }

            Text("Scan to download from the App Store")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Slide 7: All Set

    private var allSetSlide: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(OnboardingTheme.brand)

            Text("You're all set!")
                .font(.system(size: 24, weight: .semibold))

            // Setup summary
            VStack(alignment: .leading, spacing: 6) {
                ForEach(OnboardingFlowModel.SetupStep.allCases, id: \.rawValue) { step in
                    HStack(spacing: 8) {
                        setupStatusIcon(for: model.setupStatus(for: step))
                            .frame(width: 14, height: 14)
                        Text(model.setupTitle(for: step))
                            .font(.callout)
                            .foregroundStyle(
                                model.setupStatus(for: step) == .skipped ? .secondary : .primary
                            )
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared Components

    private func educationSlide(icon: String, title: String, description: String, detail: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(OnboardingTheme.brand)

            Text(title)
                .font(.system(size: 24, weight: .semibold))

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 40)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func keyCapView(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(OnboardingTheme.brand)
            .frame(width: 52, height: 52)
            .background(OnboardingTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(OnboardingTheme.divider, lineWidth: 1)
            )
    }

    private func shortcutStep(number: String, text: String) -> some View {
        VStack(spacing: 4) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(OnboardingTheme.brand, in: Circle())

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        // Invert: black modules → white, white bg → black
        let invert = CIFilter(name: "CIColorInvert")!
        invert.setValue(ciImage, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return nil }

        // MaskToAlpha: white → opaque, black → transparent
        let maskToAlpha = CIFilter(name: "CIMaskToAlpha")!
        maskToAlpha.setValue(inverted, forKey: kCIInputImageKey)
        guard let alphaImage = maskToAlpha.outputImage else { return nil }

        // Scale up for crisp rendering
        let scaled = alphaImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 120))
    }

    // MARK: - Setup Actions

    /// Run setup steps automatically, pausing on steps that need user interaction.
    private func runAutoSetupSteps() {
        guard !model.isSetupRunning else { return }
        model.isSetupRunning = true

        Task {
            // Step 1: Create ~/.balcony/
            if manager.isBalconyDirPresent {
                model.setupStepStatuses[.balconyDir] = .completed
            } else {
                model.setupStepStatuses[.balconyDir] = .inProgress
                do {
                    try manager.createBalconyDir()
                    model.setupStepStatuses[.balconyDir] = .completed
                } catch {
                    model.setupStepStatuses[.balconyDir] = .failed(error.localizedDescription)
                    model.errorMessage = error.localizedDescription
                    model.isSetupRunning = false
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(300))

            // Step 2: Install hook-handler
            if manager.isHookHandlerInstalled {
                model.setupStepStatuses[.hookHandler] = .completed
            } else {
                model.setupStepStatuses[.hookHandler] = .inProgress
                do {
                    try manager.installHookHandler()
                    model.setupStepStatuses[.hookHandler] = .completed
                } catch {
                    model.setupStepStatuses[.hookHandler] = .failed(error.localizedDescription)
                    model.errorMessage = error.localizedDescription
                    model.isSetupRunning = false
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(300))

            // Step 3: Install CLI
            if manager.isCLIInstalled {
                model.setupStepStatuses[.installCLI] = .completed
            } else {
                let result = manager.installCLI()
                switch result {
                case .success:
                    model.setupStepStatuses[.installCLI] = .completed
                case .needsAdmin:
                    model.cliNeedsAdmin = true
                    model.setupStepStatuses[.installCLI] = .pending
                    if let src = Bundle.main.path(forResource: "balcony-cli", ofType: nil) {
                        model.manualCLICommand = "sudo cp '\(src)' /usr/local/bin/balcony && sudo chmod +x /usr/local/bin/balcony"
                    }
                    model.isSetupRunning = false
                    return // Wait for user action
                case .failed(let error):
                    model.setupStepStatuses[.installCLI] = .failed(error.localizedDescription)
                    model.errorMessage = error.localizedDescription
                    model.isSetupRunning = false
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(200))

            // Step 4: Patch hooks — needs user confirmation
            if manager.areHooksPatched {
                model.setupStepStatuses[.patchHooks] = .completed
            } else {
                model.isSetupRunning = false
                return // Wait for user to tap "Patch Settings"
            }

            try? await Task.sleep(for: .milliseconds(200))

            // Step 5: Alias — needs user confirmation
            if manager.isAliasInstalled {
                model.setupStepStatuses[.aliasSetup] = .completed
            } else {
                model.isSetupRunning = false
                return // Wait for user to tap "Add Alias"
            }

            model.isSetupRunning = false
        }
    }

    /// Continue auto-setup from a specific step (after user interaction completes).
    private func continueAutoSetup(from step: OnboardingFlowModel.SetupStep) {
        Task {
            switch step {
            case .patchHooks:
                if manager.areHooksPatched {
                    model.setupStepStatuses[.patchHooks] = .completed
                    try? await Task.sleep(for: .milliseconds(200))
                    continueAutoSetup(from: .aliasSetup)
                }
                // Otherwise wait for user action

            case .aliasSetup:
                if manager.isAliasInstalled {
                    model.setupStepStatuses[.aliasSetup] = .completed
                }
                // Otherwise wait for user action

            default:
                break
            }
        }
    }

    private func installCLIWithAdmin() {
        model.errorMessage = nil
        model.setupStepStatuses[.installCLI] = .inProgress

        Task {
            do {
                try manager.installCLIWithAdmin()
                model.setupStepStatuses[.installCLI] = .completed
                model.cliNeedsAdmin = false
                try? await Task.sleep(for: .milliseconds(200))
                continueAutoSetup(from: .patchHooks)
            } catch {
                model.setupStepStatuses[.installCLI] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func performPatchHooks() {
        model.errorMessage = nil
        model.setupStepStatuses[.patchHooks] = .inProgress

        Task {
            do {
                try manager.patchHooks()
                model.setupStepStatuses[.patchHooks] = .completed
                try? await Task.sleep(for: .milliseconds(200))
                continueAutoSetup(from: .aliasSetup)
            } catch {
                model.setupStepStatuses[.patchHooks] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func performAliasInstall() {
        model.errorMessage = nil
        model.setupStepStatuses[.aliasSetup] = .inProgress

        Task {
            do {
                try manager.installAlias()
                model.setupStepStatuses[.aliasSetup] = .completed
            } catch {
                model.setupStepStatuses[.aliasSetup] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
