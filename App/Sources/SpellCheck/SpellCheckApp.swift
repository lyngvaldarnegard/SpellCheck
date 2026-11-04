import AppKit
import SwiftUI
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
    private var hotKeyMonitor: HotKeyMonitor?
    private var engine: CorrectionEngine?
    private var settingsStore: SettingsStore?
    private(set) var settings: AppSettings = .default

    func applicationDidFinishLaunching(_ notification: Notification) {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let supportDir = (urls.first ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("SpellCheck", isDirectory: true)
        settingsStore = try? SettingsStore(directory: supportDir)
        settings = settingsStore?.load() ?? .default

        let accessibility = AccessibilityTextSource()
        let backend = makeBackend(from: settings)
        let controller = StatusBarController(settings: settings)
        statusBarController = controller
        controller.appDelegate = self

        engine = CorrectionEngine(
            backend: backend,
            source: accessibility,
            confirm: { [weak controller] original, corrected in
                await ConfirmationWindowController.confirm(original: original, corrected: corrected)
            },
            onEvent: { [weak controller] event in
                Task { @MainActor in controller?.handle(event) }
            }
        )

        settingsController = SettingsWindowController(store: settingsStore, settings: settings) { [weak self] newSettings in
            Task { @MainActor in self?.applySettings(newSettings) }
        }

        hotKeyMonitor = HotKeyMonitor(hotKey: settings.hotKey) { [weak self] in
            Task { await self?.runDefaultAction() }
        }
        hotKeyMonitor?.start()

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }

    func applySettings(_ newSettings: AppSettings) {
        settings = newSettings
        hotKeyMonitor?.stop()
        hotKeyMonitor = HotKeyMonitor(hotKey: newSettings.hotKey) { [weak self] in
            Task { await self?.runDefaultAction() }
        }
        hotKeyMonitor?.start()
        statusBarController?.settings = newSettings
        engine = CorrectionEngine(
            backend: makeBackend(from: newSettings),
            source: AccessibilityTextSource(),
            confirm: { [weak self] original, corrected in
                await ConfirmationWindowController.confirm(original: original, corrected: corrected)
            },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.statusBarController?.handle(event) }
            }
        )
    }

    func openSettings() {
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func makeBackend(from settings: AppSettings) -> any CorrectionBackend {
        switch settings.backend {
        case .ruleBased:
            return RuleBasedBackend()
        case .openAICompatible:
            return OpenAICompatibleBackend(
                apiKey: settings.apiKey,
                model: settings.model,
                baseURL: settings.baseURL
            )
        }
    }

    private func runDefaultAction() async {
        guard let engine else { return }
        await engine.run(action: .fixTypos, language: settings.translationLanguage)
    }

    func runAction(_ action: BuiltinAction) async {
        guard let engine else { return }
        await engine.run(action: action, language: settings.translationLanguage)
    }

    func runCustomPrompt(_ prompt: CustomPrompt) async {
        guard let engine else { return }
        await engine.run(action: .fixTypos, customPrompt: prompt.prompt, language: settings.translationLanguage)
    }
}
