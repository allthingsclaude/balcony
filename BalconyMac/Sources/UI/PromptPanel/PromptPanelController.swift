import AppKit
import SwiftUI
import BalconyShared
import os

// MARK: - Private Panel Classes

/// Borderless panel that can still become key (accept keyboard input).
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Transparent overlay that darkens collapsed panels. Passes all mouse events through.
private class DimmingView: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 16
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// NSView wrapper providing mouse hover tracking and a dimming overlay.
private class HoverTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    let dimmingView = DimmingView()

    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        dimmingView.frame = bounds
        dimmingView.autoresizingMask = [.width, .height]
        addSubview(dimmingView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

// MARK: - PromptPanelController

/// Manages floating NSPanels that show permission and idle prompt details.
/// Multiple panels collapse into a compact deck and expand on hover,
/// like macOS notification center.
@MainActor
final class PromptPanelController {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "PromptPanelController")

    /// Active panels in stack order (index 0 = topmost).
    private var panels: [(sessionId: String, panel: NSPanel)] = []

    /// Called when the user clicks an action button. Passes (sessionId, keystroke).
    var onResponse: ((String, String) -> Void)?

    /// Called when the user submits text from the idle prompt panel. Passes (sessionId, text).
    var onTextResponse: ((String, String) -> Void)?

    // MARK: - Layout

    private static let rightMargin: CGFloat = 16
    private static let topMargin: CGFloat = 8
    /// Gap between stacked panels in expanded mode.
    private static let stackGap: CGFloat = 8
    /// Vertical peek offset for each collapsed panel behind the top one.
    private static let collapsedPeekOffset: CGFloat = 6
    /// Maximum number of panels visible in collapsed mode.
    private static let maxVisibleCollapsed: Int = 4
    /// Scale reduction per collapsed level (e.g., 0.02 = 2% smaller per level).
    private static let collapsedScaleStep: CGFloat = 0.02
    /// Dimming opacity increase per collapsed level.
    private static let collapsedDimStep: CGFloat = 0.10

    // MARK: - Hover State

    /// Whether the stack is expanded (on hover) or collapsed (default).
    private var isExpanded = false
    /// Timer used to debounce collapse when mouse moves between panels.
    private var collapseTimer: Timer?

    // MARK: - Show

    /// Show the prompt panel for an idle prompt (Claude waiting for user input).
    func showIdlePrompt(_ info: IdlePromptInfo) {
        logger.info("Showing idle prompt panel: session=\(info.sessionId)")
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

        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    /// Show the prompt panel for a permission request.
    func showPrompt(_ info: PermissionPromptInfo) {
        logger.info("Showing prompt panel: \(info.toolName) session=\(info.sessionId)")
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

        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    // MARK: - Dismiss

    /// Dismiss the prompt panel for a specific session.
    func dismissPrompt(for sessionId: String) {
        guard let index = panels.firstIndex(where: { $0.sessionId == sessionId }) else { return }

        let entry = panels.remove(at: index)
        fadeOut(entry.panel)

        if panels.count <= 1 {
            isExpanded = false
            collapseTimer?.invalidate()
            collapseTimer = nil
        }

        repositionPanels(animated: true)
        if !isExpanded {
            updateZOrdering()
        }
    }

    /// Dismiss all panels (e.g., on app termination).
    func dismissAllPanels() {
        for entry in panels {
            fadeOut(entry.panel)
        }
        panels.removeAll()
        isExpanded = false
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    // MARK: - Private — Panel Setup

    private func configureAndShow(panel: NSPanel, hostingView: NSHostingView<some View>, sessionId: String) {
        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 340)
        let height = fittingSize.height

        // Wrap in tracking view for hover detection + dimming overlay
        let trackingView = HoverTrackingView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Ensure transparent background so SwiftUI rounded corners render cleanly
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]
        // Insert hosting view below the dimming overlay
        trackingView.addSubview(hostingView, positioned: .below, relativeTo: trackingView.dimmingView)

        trackingView.onMouseEntered = { [weak self] in
            self?.handlePanelMouseEntered()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.handlePanelMouseExited()
        }
        panel.contentView = trackingView

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - width - Self.rightMargin

        let topY = screenFrame.maxY - Self.topMargin - height
        panel.setFrame(NSRect(x: x, y: topY, width: width, height: height), display: false)

        // Insert new panel at the front (top of stack)
        panels.insert((sessionId: sessionId, panel: panel), at: 0)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Fade in the new panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        repositionPanels(animated: true)
        updateZOrdering()
    }

    /// Reposition all panels based on current expanded/collapsed state.
    private func repositionPanels(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        if isExpanded || panels.count <= 1 {
            // Expanded: full vertical stacking with gaps, no scaling/dimming
            var y = screenFrame.maxY - Self.topMargin
            for entry in panels {
                let frame = entry.panel.frame
                y -= frame.height
                let newFrame = NSRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)
                y -= Self.stackGap
                applyLayout(to: entry.panel, frame: newFrame, scale: 1.0, dimming: 0, alpha: 1.0, animated: animated)
            }
        } else {
            // Collapsed: compact deck with scale + dimming for depth
            let topY = screenFrame.maxY - Self.topMargin
            for (index, entry) in panels.enumerated() {
                let frame = entry.panel.frame
                let topEdge = topY - CGFloat(index) * Self.collapsedPeekOffset
                let y = topEdge - frame.height
                let newFrame = NSRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)

                let scale = 1.0 - CGFloat(index) * Self.collapsedScaleStep
                let dimming = CGFloat(index) * Self.collapsedDimStep
                let alpha: CGFloat = index < Self.maxVisibleCollapsed ? 1.0 : 0.0

                applyLayout(to: entry.panel, frame: newFrame, scale: scale, dimming: dimming, alpha: alpha, animated: animated)
            }
        }
    }

    private func applyLayout(to panel: NSPanel, frame: NSRect, scale: CGFloat, dimming: CGFloat, alpha: CGFloat, animated: Bool) {
        let trackingView = panel.contentView as? HoverTrackingView
        let transform = CATransform3DMakeScale(scale, scale, 1.0)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = alpha
                trackingView?.dimmingView.animator().alphaValue = dimming
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            trackingView?.layer?.transform = transform
            CATransaction.commit()
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = alpha
            trackingView?.dimmingView.alphaValue = dimming
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trackingView?.layer?.transform = transform
            CATransaction.commit()
        }
    }

    /// Ensure correct z-ordering: index 0 in front.
    private func updateZOrdering() {
        for entry in panels.reversed() {
            entry.panel.orderFront(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        return panel
    }

    private func fadeOut(_ panel: NSPanel) {
        let panelRef = panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panelRef.animator().alphaValue = 0
        }, completionHandler: {
            panelRef.orderOut(nil)
        })
    }

    // MARK: - Private — Hover Detection

    private func handlePanelMouseEntered() {
        collapseTimer?.invalidate()
        collapseTimer = nil

        guard panels.count > 1, !isExpanded else { return }
        isExpanded = true
        repositionPanels(animated: true)
    }

    private func handlePanelMouseExited() {
        guard panels.count > 1, isExpanded else { return }

        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfMouseOutside()
            }
        }
    }

    /// Check if mouse has left all panels and collapse if so.
    private func collapseIfMouseOutside() {
        let mouse = NSEvent.mouseLocation
        let inAnyPanel = panels.contains { $0.panel.frame.contains(mouse) }
        guard !inAnyPanel else { return }

        isExpanded = false
        repositionPanels(animated: true)
        updateZOrdering()
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
