import Foundation
import Sparkle
import SwiftUI

/// Brings the app to the foreground when Sparkle shows an update dialog.
private class UpdaterUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Wraps Sparkle's SPUStandardUpdaterController for use in SwiftUI.
final class UpdaterService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate = UpdaterUserDriverDelegate()

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
