import AppKit
import SpellCheckCore
import SpellCheckEngine

/// Menu-bar item showing the current status and offering the action menu.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    var settings: AppSettings
    weak var appDelegate: AppDelegate?

    private var statusMenu: NSMenu!

    init(settings: AppSettings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        applyIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu(_:))
        buildMenu()
    }

    /// Applies new settings: swaps the menu-bar icon and rebuilds the menu
    /// (hot key label and custom prompts may have changed).
    func apply(_ newSettings: AppSettings) {
        settings = newSettings
        applyIcon()
        buildMenu()
    }

    private func applyIcon() {
        let style = MenuBarIconStyle.from(settingsValue: settings.menuBarIconStyle)
        if let image = style.templateImage {
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = "⌨"
        }
    }

    /// Testing hooks: the current icon image and tooltip.
    var statusIconForTesting: NSImage? { statusItem.button?.image }
    var toolTipForTesting: String? { statusItem.button?.toolTip }

    /// The menu-bar icon is just the icon: no status glyphs, no tooltips, no
    /// flashing (the old title logic was dead code in the packaged app, since
    /// the installed template image always replaced it, and the user asked for
    /// no status reporting here anyway). The cursor spinner is the sole
    /// working indicator; real errors still surface as alert windows.
    func handle(_ event: EngineEvent) {
        // Intentionally no visual status.
    }

    @objc private func toggleMenu(_ sender: Any?) {
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: statusItem.button)
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let pickerItem = NSMenuItem(
            title: "Open Prompt Picker  \(settings.hotKey.description)",
            action: #selector(openPromptPicker),
            keyEquivalent: ""
        )
        pickerItem.target = self
        menu.addItem(pickerItem)
        menu.addItem(.separator())

        let editorItem = NSMenuItem(title: "Prompt Editor…", action: #selector(openPromptEditor), keyEquivalent: "")
        editorItem.target = self
        menu.addItem(editorItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SpellCheck", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
        statusItem.menu = nil // we pop up manually so the button highlights
    }

    @objc private func openPromptPicker() {
        appDelegate?.openPromptPicker()
    }

    @objc private func openPromptEditor() {
        appDelegate?.openPromptEditor()
    }

    @objc private func openSettings() {
        appDelegate?.openSettings()
    }

    @objc private func checkForUpdates() {
        appDelegate?.checkForUpdates()
    }

    @objc private func quit() {
        appDelegate?.quit()
    }
}
