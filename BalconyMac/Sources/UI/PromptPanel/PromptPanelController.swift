import AppKit
import SwiftUI
import BalconyShared
import os

/// Manages a floating NSPanel that shows permission prompt details
/// and action buttons. The panel does not steal focus from the terminal.
@MainActor
final class PromptPanelController {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "PromptPanelController")

    private var panel: NSPanel?
    private var currentSessionId: String?

    /// Called when the user clicks an action button. Passes (sessionId, keystroke).
    var onResponse: ((String, String) -> Void)?

    /// Called when the user submits text from the idle prompt panel. Passes (sessionId, text).
    var onTextResponse: ((String, String) -> Void)?

    // MARK: - Show / Dismiss

    /// Show the prompt panel for an idle prompt (Claude waiting for user input).
    func showIdlePrompt(_ info: IdlePromptInfo) {
        logger.info("Showing idle prompt panel: session=\(info.sessionId)")

        dismissPanel()
        currentSessionId = info.sessionId

        // Capture sessionId in closures so it's stable even if currentSessionId changes.
        let sessionId = info.sessionId
        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: IdlePromptPanelView(
                info: info,
                onSubmit: { [weak self] text in
                    self?.handleTextSubmit(sessionId: sessionId, text: text)
                },
                onDismiss: { [weak self] in
                    self?.dismissPanel()
                }
            )
        )

        panel.contentView = hostingView

        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 320)
        let height = fittingSize.height

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - width - 16
            let y = screenFrame.maxY - height - 8
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    /// Show the prompt panel for a permission request.
    func showPrompt(_ info: PermissionPromptInfo) {
        logger.info("Showing prompt panel: \(info.toolName) session=\(info.sessionId)")

        // Dismiss existing panel if any
        dismissPanel()

        currentSessionId = info.sessionId

        // Capture sessionId in closure so it's stable even if currentSessionId changes.
        let sessionId = info.sessionId
        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: PromptPanelView(
                info: info,
                onAction: { [weak self] keystroke in
                    self?.handleAction(sessionId: sessionId, keystroke: keystroke)
                }
            )
        )

        panel.contentView = hostingView

        // Size to fit content
        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 320)
        let height = fittingSize.height

        // Position near top-right of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - width - 16
            let y = screenFrame.maxY - height - 8
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    /// Dismiss the prompt panel for a specific session.
    func dismissPrompt(for sessionId: String) {
        guard currentSessionId == sessionId else { return }
        dismissPanel()
    }

    /// Dismiss the current prompt panel regardless of session.
    func dismissPanel() {
        guard let panel else { return }
        let panelRef = panel
        self.panel = nil
        self.currentSessionId = nil

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panelRef.animator().alphaValue = 0
        }, completionHandler: {
            panelRef.orderOut(nil)
        })
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        return panel
    }

    private func handleAction(sessionId: String, keystroke: String) {
        logger.info("Panel action: keystroke='\(keystroke)' session=\(sessionId)")
        onResponse?(sessionId, keystroke)
        dismissPanel()
    }

    private func handleTextSubmit(sessionId: String, text: String) {
        logger.info("Panel text submit: '\(text.prefix(50))' session=\(sessionId)")
        onTextResponse?(sessionId, text)
        dismissPanel()
    }
}
