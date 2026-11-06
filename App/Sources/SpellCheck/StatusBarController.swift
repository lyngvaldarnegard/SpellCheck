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

    /// Testing hook: the menu-bar item's current tooltip.
    var toolTipForTesting: String? { statusItem.button?.toolTip }

    func handle(_ event: EngineEvent) {
        switch event {
        case .idle:
            setFallbackTitle("⌨")
            statusItem.button?.toolTip = nil
        case .working(let message):
            setFallbackTitle("⏳")
            statusItem.button?.toolTip = message
        case .succeeded:
            setFallbackTitle("✓")
            statusItem.button?.toolTip = "Done"
            flash(title: "✓")
        case .failed(let message):
            setFallbackTitle("✗")
            statusItem.button?.toolTip = message
            flash(title: "✗")
        case .replaceFailed:
            // No message, no tooltip — the user sees the document on screen and
            // asked for no replacement-failure reporting at all. The brief ✗
            // only signals that the run ended (so the app never looks stuck);
            // the paste is never repeated.
            statusItem.button?.toolTip = nil
            setFallbackTitle("✗")
            flash(title: "✗")
        case .busy(let message):
            // Menu-bar-only feedback: a second edit was requested while one is
            // still running. Nothing was edited; the user can retry after the
            // current correction finishes.
            setFallbackTitle("⏳")
            statusItem.button?.toolTip = message
        }
    }

    /// When a template image is installed the title is not rendered, so only
    /// set it as a fallback (e.g. running from `swift run` without resources).
    private func setFallbackTitle(_ title: String) {
        if statusItem.button?.image == nil {
            statusItem.button?.title = title
        }
    }

    private func flash(title: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.statusItem.button?.image == nil, self.statusItem.button?.title == title else { return }
            self.statusItem.button?.title = "⌨"
            self.statusItem.button?.toolTip = nil
        }
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
