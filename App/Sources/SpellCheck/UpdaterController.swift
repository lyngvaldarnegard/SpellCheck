import AppKit
import Sparkle

/// Wraps Sparkle's standard updater: checks the appcast feed for new versions
/// and installs them on quit. Started automatically at launch; the menu-bar
/// menu also gets a "Check for Updates…" item.
@MainActor
final class UpdaterController {
    let updaterController: SPUStandardUpdaterController

    init() {
        // Only auto-start the updater when a Sparkle public key is configured in
        // Info.plist — otherwise every launch would log/present update errors.
        let hasSigningKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        updaterController = SPUStandardUpdaterController(
            startingUpdater: hasSigningKey,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") == nil {
            let alert = NSAlert()
            alert.messageText = "Automatic updates are not configured yet"
            alert.informativeText = "New versions are published on the GitHub Releases page. In-app auto-update is enabled once releases are signed with a Sparkle key (see README)."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        updaterController.checkForUpdates(nil)
    }
}
