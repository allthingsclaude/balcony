import AppKit
import SwiftUI
import BalconyShared
import os

/// Manages floating NSPanels that show permission and idle prompt details.
/// Multiple panels stack vertically from the top-right corner of the screen.
/// Panels do not steal focus from the terminal.
@MainActor
final class PromptPanelController {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "PromptPanelController")

    /// Active panels in stack order (top to bottom). Each entry tracks the session it belongs to.
    private var panels: [(sessionId: String, panel: NSPanel)] = []

    /// Called when the user clicks an action button. Passes (sessionId, keystroke).
    var onResponse: ((String, String) -> Void)?

    /// Called when the user submits text from the idle prompt panel. Passes (sessionId, text).
    var onTextResponse: ((String, String) -> Void)?

    // MARK: - Layout

    /// Horizontal margin from right edge of screen.
    private static let rightMargin: CGFloat = 16
    /// Vertical margin from top of visible screen area.
    private static let topMargin: CGFloat = 8
    /// Gap between stacked panels.
    private static let stackGap: CGFloat = 8

    // MARK: - Show

    /// Show the prompt panel for an idle prompt (Claude waiting for user input).
    func showIdlePrompt(_ info: IdlePromptInfo) {
        logger.info("Showing idle prompt panel: session=\(info.sessionId)")

        // If a panel for this session already exists, dismiss it first
        dismissPrompt(for: info.sessionId)

        let sessionId = info.sessionId
        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: IdlePromptPanelView(
                info: info,
                onSubmit: { [weak self] text in
                    self?.handleTextSubmit(sessionId: sessionId, text: text)
                },
                onDismiss: { [weak self] in
                    self?.dismissPrompt(for: sessionId)
                }
            )
        )

        panel.contentView = hostingView
        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    /// Show the prompt panel for a permission request.
    func showPrompt(_ info: PermissionPromptInfo) {
        logger.info("Showing prompt panel: \(info.toolName) session=\(info.sessionId)")

        // If a panel for this session already exists, dismiss it first
        dismissPrompt(for: info.sessionId)

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
        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    // MARK: - Dismiss

    /// Dismiss the prompt panel for a specific session.
    func dismissPrompt(for sessionId: String) {
        guard let index = panels.firstIndex(where: { $0.sessionId == sessionId }) else { return }

        let entry = panels.remove(at: index)
        fadeOut(entry.panel)

        // Animate remaining panels to close the gap
        repositionPanels(animated: true)
    }

    /// Dismiss all panels (e.g., on app termination).
    func dismissAllPanels() {
        for entry in panels {
            fadeOut(entry.panel)
        }
        panels.removeAll()
    }

    // MARK: - Private — Panel Setup

    private func configureAndShow(panel: NSPanel, hostingView: NSHostingView<some View>, sessionId: String) {
        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 320)
        let height = fittingSize.height

        // Calculate Y position: below all existing panels
        let y = nextPanelY(forHeight: height)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - width - Self.rightMargin
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }

        panels.append((sessionId: sessionId, panel: panel))

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    /// Calculate Y position for the next panel in the stack.
    private func nextPanelY(forHeight height: CGFloat) -> CGFloat {
        guard let screen = NSScreen.main else { return 100 }
        let screenFrame = screen.visibleFrame

        // Start from top
        var y = screenFrame.maxY - Self.topMargin

        // Walk down through existing panels
        for entry in panels {
            y -= entry.panel.frame.height + Self.stackGap
        }

        // Position this panel's top edge at y
        return y - height
    }

    /// Reposition all panels in stack order (top to bottom).
    private func repositionPanels(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        var y = screenFrame.maxY - Self.topMargin

        for entry in panels {
            let frame = entry.panel.frame
            y -= frame.height
            let newFrame = NSRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)
            y -= Self.stackGap

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    entry.panel.animator().setFrame(newFrame, display: true)
                }
            } else {
                entry.panel.setFrame(newFrame, display: true)
            }
        }
    }

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

    private func fadeOut(_ panel: NSPanel) {
        let panelRef = panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panelRef.animator().alphaValue = 0
        }, completionHandler: {
            panelRef.orderOut(nil)
        })
    }

    // MARK: - Private — Callbacks

    private func handleAction(sessionId: String, keystroke: String) {
        logger.info("Panel action: keystroke='\(keystroke)' session=\(sessionId)")
        onResponse?(sessionId, keystroke)
        dismissPrompt(for: sessionId)
    }

    private func handleTextSubmit(sessionId: String, text: String) {
        logger.info("Panel text submit: '\(text.prefix(50))' session=\(sessionId)")
        onTextResponse?(sessionId, text)
        dismissPrompt(for: sessionId)
    }
}
