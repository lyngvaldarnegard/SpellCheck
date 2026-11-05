import AppKit
import SwiftUI
import ServiceManagement
import ApplicationServices
import SpellCheckCore
import SpellCheckEngine

typealias AppSettings = SpellCheckCore.Settings

@main
struct SpellCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SettingsWindowGroup {
            if let controller = appDelegate.settingsController {
                SettingsView(controller: controller)
            } else {
                Text("Loading…")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusBarController: StatusBarController!
    private(set) var settingsController: SettingsWindowController!
    private(set) var promptEditorController: PromptEditorWindowController!
    private var hotKeyMonitor: HotKeyMonitor?
    private var engine: CorrectionEngine?
    private var settingsStore: SettingsStore?
    private var updaterController: UpdaterController?
    private let textSource = AccessibilityTextSource()
    private var pickerController: PromptPickerWindowController?
    private var pendingGrab: GrabbedText?
    private(set) var settings: AppSettings = .default

    func applicationDidFinishLaunching(_ notification: Notification) {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let supportDir = (urls.first ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("SpellCheck", isDirectory: true)
        let settingsFile = supportDir.appendingPathComponent("settings.json")
        let isFirstRun = !FileManager.default.fileExists(atPath: settingsFile.path)
        settingsStore = try? SettingsStore(directory: supportDir)
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            await self.setup()
            if isFirstRun {
                self.showFirstRunNotice()
            }
        }
    }

    /// Menu-bar-only apps show no window on launch — make that obvious.
    private func showFirstRunNotice() {
        openSettings()
        let alert = NSAlert()
        alert.messageText = "SpellCheck is running"
        alert.informativeText = "Look for the spellcheck icon in the menu bar (top right). Select text in any app and press \(settings.hotKey.description) to open the prompt picker."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setup() async {
        let loaded = await settingsStore?.load() ?? .default
        let migrated = loaded.migrated()
        if migrated != loaded, let settingsStore {
            try? await settingsStore.update { _ in migrated }
        }
        settings = migrated

        let controller = StatusBarController(settings: settings)
        statusBarController = controller
        controller.appDelegate = self

        engine = CorrectionEngine(
            backend: makeBackend(from: settings),
            source: textSource,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        )

        settingsController = SettingsWindowController(settings: settings)
        settingsController.configureSave { [weak self] newSettings in
            try await self?.saveSettings(newSettings)
        }

        promptEditorController = PromptEditorWindowController(
            settings: settings,
            save: { [weak self] current, prompts in
                guard let self else { return }
                var updated = current
                updated.prompts = prompts
                try await self.saveSettings(updated)
            },
            onPromptsChanged: { [weak self] _ in
                self?.statusBarController?.apply(self?.settings ?? .default)
            }
        )

        registerHotKey()
        updaterController = UpdaterController()

        if !AXIsProcessTrusted() {
            showAccessibilityAlert()
        }

        NSApp.activate(ignoringOtherApps: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }

    // MARK: Settings persistence

    /// Persists settings to disk, then applies them. Throws when the write
    /// fails so the UI can show an error instead of silently discarding.
    private func saveSettings(_ newSettings: AppSettings) async throws {
        guard let settingsStore else {
            throw CorrectionError.backendFailed("Settings storage is unavailable")
        }
        try await settingsStore.update { _ in newSettings }
        settings = newSettings
        applySettings(newSettings)
        try applyLoginItem(newSettings)
    }

    func applySettings(_ newSettings: AppSettings) {
        settings = newSettings
        registerHotKey()
        statusBarController?.apply(newSettings)
        engine = CorrectionEngine(
            backend: makeBackend(from: newSettings),
            source: textSource,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        )
        promptEditorController?.reload(settings: newSettings)
    }

    private func applyLoginItem(_ newSettings: AppSettings) throws {
        let service = SMAppService.mainApp
        let enabled = service.status == .enabled
        if newSettings.launchAtLogin && !enabled {
            do {
                try service.register()
            } catch {
                throw CorrectionError.backendFailed("Could not enable “Launch at login”: \(error.localizedDescription)")
            }
        } else if !newSettings.launchAtLogin && enabled {
            try? service.unregister()
        }
    }

    private func makeBackend(from settings: AppSettings) -> any CorrectionBackend {
        OpenAICompatibleBackend(
            apiKey: settings.apiKey,
            model: settings.model,
            baseURL: settings.baseURL
        )
    }

    // MARK: Hot key

    private func registerHotKey() {
        hotKeyMonitor?.stop()
        let monitor = HotKeyMonitor(hotKey: settings.hotKey) { [weak self] in
            Task { @MainActor in self?.openPromptPicker() }
        }
        hotKeyMonitor = monitor
        if let failure = monitor.start() {
            ErrorPresenter.show(title: "Shortcut not registered", message: failure)
        }
    }

    // MARK: Prompt picker workflow

    /// ⌥L flow: grab the selection immediately (so the original selection and
    /// target app are captured before anything else happens), then open the
    /// prompt picker over it.
    func openPromptPicker() {
        Task { @MainActor in
            guard self.pickerController == nil else { return }
            if let engine = self.engine, await engine.isBusy { return }
            do {
                let grabbed = try await self.textSource.grab()
                self.pendingGrab = grabbed
                let picker = PromptPickerWindowController(prompts: self.settings.prompts)
                picker.onChoose = { [weak self] prompt in
                    self?.pickerController = nil
                    self?.runPrompt(prompt)
                }
                picker.onCancel = { [weak self] in
                    self?.pickerController = nil
                    self?.pendingGrab = nil
                }
                self.pickerController = picker
                picker.show()
            } catch {
                ErrorPresenter.show(title: "SpellCheck", message: CorrectionEngine.message(for: error))
            }
        }
    }

    private func runPrompt(_ prompt: Prompt) {
        guard let engine, let grabbed = pendingGrab else { return }
        pendingGrab = nil
        Task { await engine.run(prompt: prompt, on: grabbed) }
    }

    // MARK: Events

    private func handle(_ event: EngineEvent) {
        statusBarController?.handle(event)
        if case .failed(let message) = event {
            ErrorPresenter.show(title: "SpellCheck", message: message)
        }
    }

    // MARK: Windows & menu actions

    func openSettings() {
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPromptEditor() {
        promptEditorController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "SpellCheck needs Accessibility access"
        alert.informativeText = "To read and replace the selected text in other apps, enable SpellCheck under System Settings → Privacy & Security → Accessibility. If it is already listed, remove and re-add it after installing a new build."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

/// Presents errors as real alert windows — never only a menu-bar tooltip.
@MainActor
enum ErrorPresenter {
    static func show(title: String, message: String) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
