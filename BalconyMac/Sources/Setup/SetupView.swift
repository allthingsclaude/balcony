import SwiftUI

// MARK: - Setup Theme

/// Theme matching the terracotta PanelTheme aesthetic.
private enum SetupTheme {
    static let brand = Color(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0)
    static let brandDark = Color(red: 0xB8/255.0, green: 0x5A/255.0, blue: 0x3A/255.0)
    static let brandLight = Color(red: 0xF0/255.0, green: 0xC4/255.0, blue: 0xAE/255.0)

    static let surface = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.07)
                : NSColor(white: 0.0, alpha: 0.04)
        }
    ))

    static let divider = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.08)
                : NSColor(white: 0.0, alpha: 0.06)
        }
    ))
}

// MARK: - Setup View

/// First-launch setup wizard.
struct SetupView: View {
    let model: SetupFlowModel
    let manager: SetupManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if model.isOnSummary {
                summaryView
            } else {
                // Main content: sidebar + step detail
                HStack(spacing: 0) {
                    stepSidebar
                        .frame(width: 180)

                    SetupTheme.divider
                        .frame(width: 1)

                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 560, height: 420)
        .onAppear {
            runAutoSteps()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(SetupTheme.brand)

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Balcony")
                    .font(.headline)
                Text("Let's set up your Mac to work with Claude Code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Step Sidebar

    private var stepSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SetupFlowModel.visibleSteps, id: \.rawValue) { step in
                sidebarRow(for: step)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
    }

    private func sidebarRow(for step: SetupFlowModel.Step) -> some View {
        let isCurrent = model.currentStep == step
        let status = model.status(for: step)

        return HStack(spacing: 8) {
            statusIndicator(for: status)
                .frame(width: 16, height: 16)

            Text(model.title(for: step))
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrent ? SetupTheme.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    @ViewBuilder
    private func statusIndicator(for status: SetupFlowModel.StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.currentStep {
            case .balconyDir:
                autoStepContent(
                    title: "Creating Balcony directory",
                    subtitle: "~/.balcony/ stores runtime data like sockets and the hook handler."
                )
            case .hookHandler:
                autoStepContent(
                    title: "Installing hook handler",
                    subtitle: "The hook handler script bridges Claude Code events to Balcony."
                )
            case .installCLI:
                cliStepContent
            case .patchHooks:
                hooksStepContent
            case .aliasSetup:
                aliasStepContent
            case .complete:
                EmptyView()
            }

            Spacer()

            if let error = model.errorMessage {
                errorBanner(error)
            }
        }
        .padding(24)
    }

    // MARK: - Auto-run Step Content

    private func autoStepContent(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.medium))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            let status = model.status(for: model.currentStep)
            if case .inProgress = status {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working...")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - CLI Step

    private var cliStepContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install CLI")
                .font(.title3.weight(.medium))
            Text("Installs the `balcony` command to /usr/local/bin so you can launch Claude Code through Balcony.")
                .font(.body)
                .foregroundStyle(.secondary)

            let status = model.status(for: .installCLI)

            if case .inProgress = status {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing...")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else if model.cliNeedsAdmin {
                Text("Writing to /usr/local/bin requires administrator access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    Button("Install with Admin") {
                        installCLIWithAdmin()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SetupTheme.brand)

                    Button("Skip") {
                        model.stepStatuses[.installCLI] = .skipped
                        advanceToNext()
                    }
                }
                .padding(.top, 8)

                if let cmd = model.manualCLICommand {
                    Text("Or run manually:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Text(cmd)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(SetupTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                }
            } else if case .pending = status {
                Button("Install") {
                    performCLIInstall()
                }
                .buttonStyle(.borderedProminent)
                .tint(SetupTheme.brand)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Hooks Step

    private var hooksStepContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configure Claude Code hooks")
                .font(.title3.weight(.medium))
            Text("Adds Balcony event hooks to ~/.claude/settings.json so Claude Code sends notifications and permission requests to Balcony.")
                .font(.body)
                .foregroundStyle(.secondary)

            let status = model.status(for: .patchHooks)

            if case .inProgress = status {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Patching...")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else if case .pending = status {
                HStack(spacing: 12) {
                    Button("Patch Settings") {
                        performPatchHooks()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SetupTheme.brand)

                    Button("Skip") {
                        model.stepStatuses[.patchHooks] = .skipped
                        advanceToNext()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Alias Step

    private var aliasStepContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up shell alias")
                .font(.title3.weight(.medium))
            Text("Adds `alias claude=balcony` to your \(manager.shellName) profile so typing `claude` uses the Balcony wrapper.")
                .font(.body)
                .foregroundStyle(.secondary)

            if let profilePath = manager.shellProfilePath {
                Text("Will modify: \(profilePath)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            let status = model.status(for: .aliasSetup)

            if case .inProgress = status {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Adding alias...")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else if case .pending = status {
                HStack(spacing: 12) {
                    Button("Add Alias") {
                        performAliasInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SetupTheme.brand)

                    Button("Skip") {
                        model.stepStatuses[.aliasSetup] = .skipped
                        advanceToNext()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(SetupTheme.brand)

            Text("You're all set!")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(SetupFlowModel.visibleSteps, id: \.rawValue) { step in
                    HStack(spacing: 8) {
                        statusIndicator(for: model.status(for: step))
                            .frame(width: 14, height: 14)
                        Text(model.title(for: step))
                            .font(.callout)
                            .foregroundStyle(
                                model.status(for: step) == .skipped ? .secondary : .primary
                            )
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Get Started") {
                manager.markComplete()
                model.onComplete?()
            }
            .buttonStyle(.borderedProminent)
            .tint(SetupTheme.brand)
            .controlSize(.large)

            Spacer()
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error Banner

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

    // MARK: - Actions

    /// Run steps 1-2 automatically on appear.
    private func runAutoSteps() {
        Task {
            // Step 1: Create ~/.balcony/
            if manager.isBalconyDirPresent {
                model.stepStatuses[.balconyDir] = .completed
            } else {
                model.stepStatuses[.balconyDir] = .inProgress
                do {
                    try manager.createBalconyDir()
                    model.stepStatuses[.balconyDir] = .completed
                } catch {
                    model.stepStatuses[.balconyDir] = .failed(error.localizedDescription)
                    model.errorMessage = error.localizedDescription
                    return
                }
            }

            // Brief pause so user sees progress
            try? await Task.sleep(for: .milliseconds(300))
            model.currentStep = .hookHandler

            // Step 2: Install hook-handler
            if manager.isHookHandlerInstalled {
                model.stepStatuses[.hookHandler] = .completed
            } else {
                model.stepStatuses[.hookHandler] = .inProgress
                do {
                    try manager.installHookHandler()
                    model.stepStatuses[.hookHandler] = .completed
                } catch {
                    model.stepStatuses[.hookHandler] = .failed(error.localizedDescription)
                    model.errorMessage = error.localizedDescription
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(300))

            // Move to CLI step — auto-attempt if already installed
            model.currentStep = .installCLI
            if manager.isCLIInstalled {
                model.stepStatuses[.installCLI] = .completed
                try? await Task.sleep(for: .milliseconds(200))
                model.currentStep = .patchHooks
            }

            // Auto-advance past hooks if already patched
            if manager.areHooksPatched {
                model.stepStatuses[.patchHooks] = .completed
                try? await Task.sleep(for: .milliseconds(200))
                model.currentStep = .aliasSetup
            }

            // Auto-advance past alias if already installed
            if manager.isAliasInstalled {
                model.stepStatuses[.aliasSetup] = .completed
                try? await Task.sleep(for: .milliseconds(200))
                model.currentStep = .complete
            }
        }
    }

    private func performCLIInstall() {
        model.errorMessage = nil
        model.stepStatuses[.installCLI] = .inProgress

        Task {
            let result = manager.installCLI()
            switch result {
            case .success:
                model.stepStatuses[.installCLI] = .completed
                advanceToNext()
            case .needsAdmin:
                model.cliNeedsAdmin = true
                model.stepStatuses[.installCLI] = .pending
                if let src = Bundle.main.path(forResource: "balcony-cli", ofType: nil) {
                    model.manualCLICommand = "sudo cp '\(src)' /usr/local/bin/balcony && sudo chmod +x /usr/local/bin/balcony"
                }
            case .failed(let error):
                model.stepStatuses[.installCLI] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func installCLIWithAdmin() {
        model.errorMessage = nil
        model.stepStatuses[.installCLI] = .inProgress

        Task {
            do {
                try manager.installCLIWithAdmin()
                model.stepStatuses[.installCLI] = .completed
                model.cliNeedsAdmin = false
                advanceToNext()
            } catch {
                model.stepStatuses[.installCLI] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func performPatchHooks() {
        model.errorMessage = nil
        model.stepStatuses[.patchHooks] = .inProgress

        Task {
            do {
                try manager.patchHooks()
                model.stepStatuses[.patchHooks] = .completed
                advanceToNext()
            } catch {
                model.stepStatuses[.patchHooks] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func performAliasInstall() {
        model.errorMessage = nil
        model.stepStatuses[.aliasSetup] = .inProgress

        Task {
            do {
                try manager.installAlias()
                model.stepStatuses[.aliasSetup] = .completed
                advanceToNext()
            } catch {
                model.stepStatuses[.aliasSetup] = .failed(error.localizedDescription)
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func advanceToNext() {
        model.errorMessage = nil
        guard let nextStep = SetupFlowModel.Step(rawValue: model.currentStep.rawValue + 1) else {
            model.currentStep = .complete
            return
        }
        model.currentStep = nextStep
    }
}
