import AppKit
import SwiftUI

/// Manages a floating NSWindow hosting the setup wizard.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?
    private let model = SetupFlowModel()
    private let manager = SetupManager()

    /// Show the setup wizard window.
    /// - Parameter onComplete: Called when the user finishes or dismisses the wizard.
    func showSetupWindow(onComplete: @escaping () -> Void) {
        // Reuse existing window if already open
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        model.onComplete = { [weak self] in
            self?.closeWindow()
            onComplete()
        }

        let view = SetupView(model: model, manager: manager)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Balcony Setup"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.delegate = WindowCloseDelegate(onClose: { [weak self] in
            self?.handleWindowClose(onComplete: onComplete)
        })

        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the setup window.
    func closeWindow() {
        window?.close()
        window = nil
    }

    /// Access the setup manager (for "Re-run Setup" in preferences).
    var setupManager: SetupManager {
        manager
    }

    /// Handle window close — if setup isn't complete, mark it complete anyway
    /// to avoid being stuck in a loop. Services need to start.
    private func handleWindowClose(onComplete: @escaping () -> Void) {
        if !manager.isSetupComplete {
            manager.markComplete()
        }
        window = nil
        onComplete()
    }
}

// MARK: - Window Close Delegate

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
