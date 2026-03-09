import AppKit
import SwiftUI
import BalconyShared
import os

// MARK: - Private Panel Classes

/// Borderless panel that can still become key (accept keyboard input).
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Called when the user presses ESC to dismiss the panel.
    var onCancel: (() -> Void)?

    /// Returns true if backspace should be consumed (voice recording is active).
    var onBackspace: (() -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onCancel?()
            return
        }
        // Backspace (keyCode 51) during voice recording
        if event.type == .keyDown, event.keyCode == 51, onBackspace?() == true {
            return
        }
        super.sendEvent(event)
    }
}

/// Transparent overlay that darkens collapsed panels. Passes all mouse events through.
private class DimmingView: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// NSView wrapper providing mouse hover tracking, drag/swipe-to-dismiss, and a dimming overlay.
private class HoverTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onSwipeDismiss: (() -> Void)?
    let dimmingView = DimmingView()

    override var isOpaque: Bool { false }

    /// Horizontal offset accumulated during a drag or scroll gesture.
    private var dragOffsetX: CGFloat = 0
    /// Whether a mouse drag is in progress.
    private var isDragging = false
    /// The dismiss threshold (points). Beyond this the panel is dismissed on release.
    private static let dismissThreshold: CGFloat = 80

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

    // MARK: - Drag to dismiss (mouse)

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragOffsetX = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        dragOffsetX += event.deltaX
        // Only allow dragging to the right
        let offset = max(dragOffsetX, 0)
        applyDragOffset(offset)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let offset = max(dragOffsetX, 0)
        dragOffsetX = 0

        if offset > Self.dismissThreshold {
            onSwipeDismiss?()
        } else {
            snapBack()
        }
    }

    // MARK: - Scroll/swipe to dismiss (trackpad / Magic Mouse)

    /// Timer that fires when scroll events stop arriving, resolving the gesture.
    private var scrollIdleTimer: Timer?

    override func scrollWheel(with event: NSEvent) {
        // Only handle horizontal scrolls
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }

        dragOffsetX += event.scrollingDeltaX
        let offset = max(dragOffsetX, 0)
        applyDragOffset(offset)

        // Reset idle timer on every scroll event
        scrollIdleTimer?.invalidate()
        scrollIdleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.resolveScrollGesture()
        }

        // Also resolve immediately on explicit terminal phases
        let isTerminal = event.phase == .ended || event.phase == .cancelled
            || event.momentumPhase == .ended || event.momentumPhase == .cancelled
        if isTerminal {
            scrollIdleTimer?.invalidate()
            scrollIdleTimer = nil
            resolveScrollGesture()
        }
    }

    private func resolveScrollGesture() {
        let finalOffset = max(dragOffsetX, 0)
        dragOffsetX = 0
        if finalOffset > Self.dismissThreshold {
            onSwipeDismiss?()
        } else {
            snapBack()
        }
    }

    // MARK: - Drag helpers

    private func applyDragOffset(_ offset: CGFloat) {
        guard let panel = window else { return }
        // Shift panel to the right and fade proportionally
        let progress = min(offset / (Self.dismissThreshold * 1.5), 1.0)
        var frame = panel.frame
        // Store original x on first move
        frame.origin.x = originalPanelX + offset
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1.0 - progress * 0.6
    }

    private func snapBack() {
        guard let panel = window else { return }
        var frame = panel.frame
        frame.origin.x = originalPanelX
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1.0
        }
    }

    /// The panel's original X position before any drag offset.
    var originalPanelX: CGFloat = 0
}

// MARK: - PromptPanelController

/// Manages floating NSPanels styled as native macOS notifications for
/// permission requests, idle prompts, and multi-option questions.
/// Multiple panels collapse into a compact deck and expand on hover.
@MainActor
final class PromptPanelController {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "PromptPanelController")

    /// Active panels in stack order (index 0 = topmost).
    private var panels: [(sessionId: String, panel: NSPanel)] = []

    /// Voice transcriber for dictation input. Set by AppDelegate.
    var voiceTranscriber: VoiceTranscriber?

    /// Called when the user clicks an action button. Passes (sessionId, keystroke).
    var onResponse: ((String, String) -> Void)?

    /// Called when the user submits text from the idle prompt panel. Passes (sessionId, text).
    var onTextResponse: ((String, String) -> Void)?

    /// Called when the user types a character in the idle prompt text field. Passes (sessionId, keystroke).
    var onTyping: ((String, String) -> Void)?

    /// Called when the user selects a multi-option choice. Passes (sessionId, arrow key sequence).
    var onMultiOptionResponse: ((String, String) -> Void)?

    /// Called when the user selects "Other" in a multi-option prompt and types text.
    /// Passes (sessionId, arrow key sequence to navigate to Other, typed text).
    var onMultiOptionOtherResponse: ((String, String, String) -> Void)?

    /// Called when the user clicks "Focus" to switch to the terminal/IDE. Passes sessionId.
    var onFocus: ((String) -> Void)?

    /// Called when all questions in an AskUserQuestion are answered.
    /// Passes (sessionId, info with original toolInput, answers dict: [questionText: answerLabel]).
    var onAskUserQuestionSubmit: ((String, AskUserQuestionInfo, [String: String]) -> Void)?

    // MARK: - Layout

    private static let rightMargin: CGFloat = 16
    private static let topMargin: CGFloat = 8
    private static let stackGap: CGFloat = 8
    private static let collapsedPeekOffset: CGFloat = 6
    private static let maxVisibleCollapsed: Int = 4
    private static let collapsedScaleStep: CGFloat = 0.02
    private static let collapsedDimStep: CGFloat = 0.10

    // MARK: - Hover State

    private var isExpanded = false
    private var collapseTimer: Timer?

    // MARK: - Show

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
                },
                onFocus: { [weak self] in
                    self?.onFocus?(sessionId)
                },
                onDismiss: { [weak self] in
                    self?.dismissPrompt(for: sessionId)
                }
            )
        )

        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    /// Show the prompt panel for an idle prompt (Claude waiting for user input).
    func showIdlePrompt(_ info: IdlePromptInfo) {
        logger.info("Showing idle prompt panel: session=\(info.sessionId)")
        dismissPrompt(for: info.sessionId)

        let sessionId = info.sessionId
        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: IdlePromptPanelView(
                info: info,
                voiceTranscriber: voiceTranscriber,
                onSubmit: { [weak self] text in
                    self?.handleTextSubmit(sessionId: sessionId, text: text)
                },
                onTyping: { [weak self] keystroke in
                    self?.onTyping?(sessionId, keystroke)
                },
                onFocus: { [weak self] in
                    self?.onFocus?(sessionId)
                },
                onDismiss: { [weak self] in
                    self?.dismissPrompt(for: sessionId)
                }
            )
        )

        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    /// Show the prompt panel for a multi-option question (AskUserQuestion).
    func showMultiOptionPrompt(_ info: IdlePromptInfo, options: [ParsedOption]) {
        logger.info("Showing multi-option panel: session=\(info.sessionId) options=\(options.count)")
        dismissPrompt(for: info.sessionId)

        let sessionId = info.sessionId
        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: MultiOptionPanelView(
                info: info,
                options: options,
                onSelect: { [weak self] option in
                    self?.handleMultiOptionSelect(sessionId: sessionId, option: option, allOptions: options)
                },
                onTextSubmit: { [weak self] text in
                    // "Other" option: navigate to it, activate, type text
                    self?.handleMultiOptionOther(sessionId: sessionId, text: text, options: options)
                },
                onFocus: { [weak self] in
                    self?.onFocus?(sessionId)
                },
                onDismiss: { [weak self] in
                    self?.dismissPrompt(for: sessionId)
                }
            )
        )

        configureAndShow(panel: panel, hostingView: hostingView, sessionId: sessionId)
    }

    /// Show the prompt panel for an AskUserQuestion tool call with structured options.
    func showAskUserQuestion(_ info: AskUserQuestionInfo) {
        logger.info("Showing AskUserQuestion panel: session=\(info.sessionId) questions=\(info.questions.count)")
        dismissPrompt(for: info.sessionId)

        let sessionId = info.sessionId
        let panel = makePanel()
        let hostingView = NSHostingView(
            rootView: AskUserQuestionPanelView(
                info: info,
                onComplete: { [weak self] answers in
                    self?.handleAskUserQuestionComplete(sessionId: sessionId, info: info, answers: answers)
                },
                onFocus: { [weak self] in
                    self?.onFocus?(sessionId)
                },
                onDismiss: { [weak self] in
                    self?.dismissPrompt(for: sessionId)
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

        // Restore focus to the previously active app after handling a panel
        restorePreviousApp()
    }

    /// Whether there are any visible panels.
    var hasPanels: Bool { !panels.isEmpty }

    /// The session ID of the frontmost panel, if any.
    var frontmostSessionId: String? { panels.first?.sessionId }

    /// Whether the user is actively interacting with panels (via hotkey activation).
    /// When true, stdin activity from the terminal should be ignored to prevent
    /// panels from being dismissed by focus-lost events.
    private(set) var isPanelActive = false

    /// Timestamp of the last focus restore, used to suppress stdin noise from app switching.
    private(set) var lastRestoreTime: TimeInterval = 0

    /// The app that was active before the panel was focused via hotkey.
    private var previousApp: NSRunningApplication?

    /// Activate the frontmost panel and make it key so it accepts keyboard input.
    func activateFrontmostPanel() {
        guard let entry = panels.first else { return }
        logger.info("[HOTKEY] Activating panel for session=\(entry.sessionId) panels=\(self.panels.count) isKey=\(entry.panel.isKeyWindow)")
        // Remember the currently active app so we can restore focus after dismiss
        previousApp = NSWorkspace.shared.frontmostApplication
        isPanelActive = true
        NSApp.activate(ignoringOtherApps: true)
        entry.panel.makeKeyAndOrderFront(nil)
        // Explicitly focus the first editable text field — SwiftUI's @FocusState
        // from onAppear doesn't re-fire when the panel is re-activated.
        focusFirstTextField(in: entry.panel)
        logger.info("[HOTKEY] Panel activated: isKey=\(entry.panel.isKeyWindow) firstResponder=\(String(describing: entry.panel.firstResponder))")
    }

    /// Walk the view hierarchy to find and focus the first editable NSTextField.
    private func focusFirstTextField(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        if let textField = findEditableTextField(in: contentView) {
            window.makeFirstResponder(textField)
        }
    }

    private func findEditableTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let textField = subview as? NSTextField, textField.isEditable {
                return textField
            }
            if let found = findEditableTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    /// Restore focus to the app that was active before the panel was focused.
    private func restorePreviousApp() {
        // Only fully clear the active flag when all panels are gone
        if panels.isEmpty {
            isPanelActive = false
        }
        lastRestoreTime = ProcessInfo.processInfo.systemUptime
        guard let app = previousApp else { return }
        previousApp = nil
        app.activate()
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
        dismissVoiceOnlyPanel()
    }

    // MARK: - Voice-Only Panel

    /// Standalone voice recording panel shown when no notification panel is active.
    private var voiceOnlyPanel: NSPanel?

    /// The app that was frontmost when standalone voice recording started.
    private(set) var voiceTargetApp: NSRunningApplication?

    /// Show a minimal floating panel for voice-only recording.
    func showVoiceOnlyPanel() {
        guard let transcriber = voiceTranscriber else { return }
        dismissVoiceOnlyPanel()

        let panel = makePanel()
        let hostingView = NSHostingView(rootView: VoiceOnlyPanelView(voiceTranscriber: transcriber))

        // Wire backspace for word deletion
        if let keyablePanel = panel as? KeyablePanel {
            keyablePanel.onBackspace = { [weak self] in
                guard let t = self?.voiceTranscriber, t.isRecording else { return false }
                t.deleteLastWord()
                return true
            }
        }

        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 340)
        let height = fittingSize.height

        // Position in top-right corner of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - width - 16
            let y = screenFrame.maxY - height - 8
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }

        panel.contentView = hostingView
        panel.alphaValue = 0

        let frontApp = NSWorkspace.shared.frontmostApplication
        previousApp = frontApp
        voiceTargetApp = frontApp
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        voiceOnlyPanel = panel
    }

    /// Dismiss the standalone voice-only panel.
    func dismissVoiceOnlyPanel() {
        guard let panel = voiceOnlyPanel else { return }
        voiceOnlyPanel = nil
        fadeOut(panel)
        restorePreviousApp()
    }

    // MARK: - Private — Panel Setup

    private func configureAndShow(panel: NSPanel, hostingView: NSHostingView<some View>, sessionId: String) {
        // Wire up ESC key to dismiss
        if let keyablePanel = panel as? KeyablePanel {
            keyablePanel.onCancel = { [weak self] in
                self?.dismissPrompt(for: sessionId)
            }
            keyablePanel.onBackspace = { [weak self] in
                guard let transcriber = self?.voiceTranscriber, transcriber.isRecording else { return false }
                transcriber.deleteLastWord()
                return true
            }
        }

        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 340)
        let height = fittingSize.height

        // Wrap in tracking view for hover detection + dimming overlay
        let trackingView = HoverTrackingView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Clip hosting view to rounded corners so the NSVisualEffectView
        // background doesn't leak at the corners
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 14
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
        trackingView.onSwipeDismiss = { [weak self] in
            self?.dismissPrompt(for: sessionId)
        }
        panel.contentView = trackingView

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - width - Self.rightMargin

        let topY = screenFrame.maxY - Self.topMargin - height
        panel.setFrame(NSRect(x: x, y: topY, width: width, height: height), display: false)
        trackingView.originalPanelX = x

        // Insert new panel at the front (top of stack)
        panels.insert((sessionId: sessionId, panel: panel), at: 0)

        // Start slightly below final position for slide-up entrance
        let slideOffset: CGFloat = 8
        var startFrame = panel.frame
        startFrame.origin.y -= slideOffset
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Fade in + slide up
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var endFrame = startFrame
            endFrame.origin.y += slideOffset
            panel.animator().setFrame(endFrame, display: true)
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
            var y = screenFrame.maxY - Self.topMargin
            for entry in panels {
                let frame = entry.panel.frame
                y -= frame.height
                let newFrame = NSRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)
                y -= Self.stackGap
                applyLayout(to: entry.panel, frame: newFrame, scale: 1.0, dimming: 0, alpha: 1.0, animated: animated)
            }
        } else {
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
        trackingView?.originalPanelX = frame.origin.x
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
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        return panel
    }

    private func fadeOut(_ panel: NSPanel) {
        let panelRef = panel
        var targetFrame = panelRef.frame
        targetFrame.origin.x += 40
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panelRef.animator().alphaValue = 0
            panelRef.animator().setFrame(targetFrame, display: true)
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
        // Fire callback BEFORE dismiss — dismiss can trigger async side-effects
        // that remove the PTY mapping needed to deliver the text.
        onTextResponse?(sessionId, text)
        dismissPrompt(for: sessionId)
    }

    private func handleMultiOptionSelect(sessionId: String, option: ParsedOption, allOptions: [ParsedOption]) {
        logger.info("Multi-option select: option=\(option.index) '\(option.label)' session=\(sessionId)")

        // Navigate with arrow keys: option 1 is default cursor position,
        // so send (index - 1) down arrows + Enter
        let downCount = option.index - 1
        var sequence = ""
        for _ in 0..<downCount {
            sequence += "\u{1b}[B"  // Down arrow
        }
        sequence += "\r"  // Enter

        onMultiOptionResponse?(sessionId, sequence)
        dismissPrompt(for: sessionId)
    }

    private func handleMultiOptionOther(sessionId: String, text: String, options: [ParsedOption]) {
        guard let otherOption = options.first(where: { $0.isOther }) else {
            // No "Other" option found — fall back to plain text submit
            handleTextSubmit(sessionId: sessionId, text: text)
            return
        }

        logger.info("Multi-option 'Other': option=\(otherOption.index) text='\(text.prefix(50))' session=\(sessionId)")

        // Build navigation sequence to the "Other" option
        let downCount = otherOption.index - 1
        var sequence = ""
        for _ in 0..<downCount {
            sequence += "\u{1b}[B"  // Down arrow
        }
        sequence += "\r"  // Enter to activate "Other" text input

        onMultiOptionOtherResponse?(sessionId, sequence, text)
        dismissPrompt(for: sessionId)
    }

    // MARK: - Private — AskUserQuestion Handlers

    /// Build the answers dict from the view's collected answers and fire the submit callback.
    private func handleAskUserQuestionComplete(sessionId: String, info: AskUserQuestionInfo, answers: [AskUserQuestionAnswer]) {
        logger.info("AskUserQuestion complete: \(answers.count) answer(s) session=\(sessionId)")

        // Build answers dict: question text → selected option label (or typed text)
        var answersDict: [String: String] = [:]
        for (i, answer) in answers.enumerated() {
            guard i < info.questions.count else { break }
            let questionText = info.questions[i].question
            switch answer {
            case .option(let label):
                answersDict[questionText] = label
            case .other(let text):
                answersDict[questionText] = text
            }
        }

        onAskUserQuestionSubmit?(sessionId, info, answersDict)
        dismissPrompt(for: sessionId)
    }
}
