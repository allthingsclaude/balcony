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

    // MARK: - Show / Dismiss

    /// Show the prompt panel for a permission request.
    func showPrompt(_ info: PermissionPromptInfo) {
        logger.info("Showing prompt panel: \(info.toolName) session=\(info.sessionId)")

        // Dismiss existing panel if any
        dismissPanel()

        currentSessionId = info.sessionId

        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: PromptPanelView(
                info: info,
                onAction: { [weak self] keystroke in
                    self?.handleAction(keystroke: keystroke)
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

    private func handleAction(keystroke: String) {
        guard let sessionId = currentSessionId else {
            logger.warning("Action received but no active session")
            return
        }

        logger.info("Panel action: keystroke='\(keystroke)' session=\(sessionId)")
        onResponse?(sessionId, keystroke)
        dismissPanel()
    }
}
