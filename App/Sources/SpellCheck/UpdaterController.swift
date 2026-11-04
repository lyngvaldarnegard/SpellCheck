import AppKit
import Sparkle

/// Wraps Sparkle's standard updater: checks the appcast feed for new versions
/// and installs them on quit. Started automatically at launch; the menu-bar
/// menu also gets a "Check for Updates…" item.
@MainActor
final class UpdaterController {
    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
