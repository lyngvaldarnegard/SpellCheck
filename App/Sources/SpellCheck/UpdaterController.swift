import AppKit
import Sparkle

/// Wraps Sparkle's standard updater: checks the appcast feed for new versions
/// and installs them. Auto-starts only when a Sparkle public key
/// (`SUPublicEDKey`) is configured in Info.plist — without it, Sparkle cannot
/// verify update signatures and must stay disabled.
@MainActor
final class UpdaterController {
    let updaterController: SPUStandardUpdaterController

    init() {
        let hasSigningKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        updaterController = SPUStandardUpdaterController(
            startingUpdater: hasSigningKey,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else {
            let alert = NSAlert()
            alert.messageText = "Automatic updates are not configured yet"
            alert.informativeText = """
            In-app updates need two things that are not set up yet:
            1. A Sparkle signing key pair — run Sparkle's generate_keys on a Mac, \
            add the private key as the SPARKLE_PRIVATE_KEY repository secret, and \
            put the public key (SUPublicEDKey) in App/Info.plist.
            2. A feed the app can read without private credentials — the repo is \
            private, so appcast.xml and release zips must be published somewhere \
            public (see README, “Auto-update setup”).

            Until then, download new versions from the GitHub Releases page.
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        updaterController.checkForUpdates(nil)
    }
}
