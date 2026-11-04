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
        statusItem.button?.title = "⌨"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu(_:))
        buildMenu()
    }

    func handle(_ event: EngineEvent) {
        switch event {
        case .idle:
            statusItem.button?.title = "⌨"
        case .working(let message):
            statusItem.button?.title = "⏳"
            statusItem.button?.toolTip = message
        case .succeeded:
            statusItem.button?.title = "✓"
            statusItem.button?.toolTip = nil
            flash(title: "✓")
        case .failed(let message):
            statusItem.button?.title = "✗"
            statusItem.button?.toolTip = message
            flash(title: "✗")
        }
    }

    private func flash(title: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.statusItem.button?.title == title else { return }
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

        for action in BuiltinAction.allCases {
            let item = NSMenuItem(title: action.rawValue, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            menu.addItem(item)
        }
        if !settings.customPrompts.isEmpty {
            menu.addItem(.separator())
            for prompt in settings.customPrompts {
                let item = NSMenuItem(title: prompt.name, action: #selector(runCustomPrompt(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = prompt
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let hotKeyItem = NSMenuItem(title: "Hot Key: \(settings.hotKey.description)", action: nil, keyEquivalent: "")
        menu.addItem(hotKeyItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit SpellCheck", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
        statusItem.menu = nil // we pop up manually so the button highlights
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? BuiltinAction else { return }
        Task { await appDelegate?.runAction(action) }
    }

    @objc private func runCustomPrompt(_ sender: NSMenuItem) {
        guard let prompt = sender.representedObject as? CustomPrompt else { return }
        Task { await appDelegate?.runCustomPrompt(prompt) }
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
