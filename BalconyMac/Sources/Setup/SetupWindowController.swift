import AppKit
import SwiftUI

/// Manages a floating NSWindow hosting the setup wizard.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?
    private var windowDelegate: WindowCloseDelegate?
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

        // Clean up any stale window reference
        window = nil
        windowDelegate = nil

        model.reset()
        model.onComplete = { [weak self] in
            self?.closeWindow()
            onComplete()
        }

        let view = SetupView(model: model, manager: manager)
        let hostingView = NSHostingView(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Balcony Setup"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.level = .floating
        newWindow.isMovableByWindowBackground = true

        // Store delegate strongly so it isn't deallocated
        let delegate = WindowCloseDelegate(onClose: { [weak self] in
            self?.handleWindowClose(onComplete: onComplete)
        })
        self.windowDelegate = delegate
        newWindow.delegate = delegate

        self.window = newWindow

        // Close Settings window so setup appears clearly
        for w in NSApp.windows where w != newWindow && w.isVisible {
            if w.title == "Settings" || w.title == "Preferences" {
                w.close()
            }
        }

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the setup window.
    func closeWindow() {
        window?.close()
        window = nil
        windowDelegate = nil
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
        windowDelegate = nil
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
