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
        // No SwiftUI window scene: the Settings and Prompt Editor windows are
        // managed manually by AppDelegate as NSWindowControllers. A SwiftUI
        // WindowGroup here produced a stray "Loading…" window that macOS state
        // restoration could bring forward (and switch Spaces) when the app
        // activated for the picker (issue #12).
        Settings {
            EmptySettingsScene()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

/// Placeholder for the never-opened Settings scene (all real windows are
/// NSWindowControllers created in AppDelegate). Without a scene the SwiftUI
/// App would launch no runloop-managed windows at all — this keeps the
/// @main struct valid without ever showing a window.
private struct EmptySettingsScene: View {
    var body: some View { EmptyView() }
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
    /// Set synchronously when a picker session starts opening, so repeated
    /// ⌥L presses or menu clicks while the (potentially slow) text grab is
    /// still running cannot open a second, overlapping picker session.
    private var pickerSessionActive = false
    /// SpellCheck's own windows temporarily lowered below other apps' windows
    /// while the picker is up, so activating SpellCheck for keyboard focus
    /// does not raise Settings / Prompt Editor over the user's work.
    private var loweredWindows: [NSWindow] = []
    /// True while a correction started from the picker is still running —
    /// SpellCheck's own windows stay below other apps' windows until it
    /// finishes, so nothing of ours jumps forward mid-workflow.
    private var windowsLoweredForRun = false
    private var workingIndicator: WorkingIndicatorController?
    /// Learns per-model response times (persisted) to drive the progress ring.
    private var responseTimeEstimator: ResponseTimeEstimator?
    /// UTF-16 length of the captured text of the run currently in flight.
    private var lastRunInputLength = 0
    private(set) var settings: AppSettings = .default

    func applicationDidFinishLaunching(_ notification: Notification) {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let supportDir = (urls.first ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("SpellCheck", isDirectory: true)
        let settingsFile = supportDir.appendingPathComponent("settings.json")
        let isFirstRun = !FileManager.default.fileExists(atPath: settingsFile.path)
        responseTimeEstimator = ResponseTimeEstimator(
            fileURL: supportDir.appendingPathComponent("response-times.json")
        )
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
            sharedPrompt: settings.sharedPrompt,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        )

        settingsController = SettingsWindowController(settings: settings)
        settingsController.responseTimeStats = { [weak self] in
            self?.responseTimeEstimator?.statistics() ?? []
        }
        settingsController.purgeUnknownModels = { [weak self] models in
            self?.responseTimeEstimator?.purgeModels(notIn: models)
        }
        settingsController.configureSave { [weak self] newSettings in
            guard let self else { return }
            // The Settings window never edits prompts — always keep the
            // live prompt list so a stale Settings snapshot cannot wipe
            // prompts created or edited in the Prompt Editor.
            var merged = newSettings
            merged.prompts = self.settings.prompts
            try await self.saveSettings(merged)
        }

        promptEditorController = PromptEditorWindowController(
            prompts: settings.prompts,
            save: { [weak self] prompts in
                guard let self else { return }
                var updated = self.settings
                updated.prompts = prompts
                try await self.saveSettings(updated)
            },
            onPromptsChanged: { [weak self] _ in
                self?.statusBarController?.apply(self?.settings ?? .default)
            }
        )

        registerHotKey()
        workingIndicator = WorkingIndicatorController()
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
        let old = settings
        settings = newSettings
        // Autosave fires often; only redo the expensive/global things when
        // the relevant settings actually changed. Recreating the engine on
        // every keystroke would also drop the busy flag of a running
        // correction, so backend-affecting changes are compared explicitly.
        if old.hotKey != newSettings.hotKey {
            registerHotKey()
        }
        statusBarController?.apply(newSettings)
        if old.apiKey != newSettings.apiKey
            || old.model != newSettings.model
            || old.backupModel != newSettings.backupModel
            || old.whitelistedModels != newSettings.whitelistedModels
            || old.baseURL != newSettings.baseURL
            || old.sharedPrompt != newSettings.sharedPrompt {
            engine = CorrectionEngine(
                backend: makeBackend(from: newSettings),
                source: textSource,
                sharedPrompt: newSettings.sharedPrompt,
                onEvent: { [weak self] event in
                    Task { @MainActor in self?.handle(event) }
                }
            )
        }
        promptEditorController?.reload(prompts: newSettings.prompts)
        settingsController?.reload(settings: newSettings)
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
        let apiKey = settings.apiKey
        let baseURL = settings.baseURL
        // A model whitelist takes precedence: the user approves which models
        // are acceptable (quality/cost), and the app automatically serves
        // each request from the fastest one, falling through the ranked list
        // on retryable failures.
        let trimmedWhitelist = settings.whitelistedModels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !trimmedWhitelist.isEmpty {
            // Capture the thread-safe estimator directly (it is an
            // @unchecked Sendable class with an internal lock), never the
            // main-actor-isolated self.
            let estimator = responseTimeEstimator
            return RankedModelBackend(
                models: trimmedWhitelist,
                makeBackend: { model in
                    OpenAICompatibleBackend(apiKey: apiKey, model: model, baseURL: baseURL)
                },
                estimatedSeconds: { model in
                    estimator?.estimate(model: model, inputLength: 1000)
                }
            )
        }
        return FallbackBackend(
            primary: OpenAICompatibleBackend(apiKey: apiKey, model: settings.model, baseURL: baseURL),
            backupModel: settings.backupModel
        ) { model in
            OpenAICompatibleBackend(apiKey: apiKey, model: model, baseURL: baseURL)
        }
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
        // Synchronous guard: the grab below can take a moment (Accessibility
        // round-trips), and without this flag two rapid activations could both
        // pass the check and open two overlapping pickers (one of them leaked
        // with its mouse monitors still installed).
        guard !pickerSessionActive else { return }
        pickerSessionActive = true
        Task { @MainActor in
            // The picker opens even while a correction is running — the user
            // must always get a visible response. If a prompt is then chosen
            // while the engine is busy, the engine reports `.busy` instead of
            // silently dropping the request (no duplicate request or paste).
            do {
                let grabbed = try await self.textSource.grab()
                self.pendingGrab = grabbed
                let picker = PromptPickerWindowController(prompts: self.settings.prompts)
                picker.onChoose = { [weak self] prompt in
                    guard let self else { return }
                    let grabbed = self.pendingGrab
                    let willRun = self.engine != nil && grabbed != nil
                    self.finishPickerSession(startedRun: willRun)
                    if willRun {
                        self.runPrompt(prompt, on: grabbed)
                    }
                }
                picker.onCancel = { [weak self] in
                    guard let self else { return }
                    let grabbed = self.pendingGrab
                    self.finishPickerSession()
                    // Give the keyboard back to the app the text came from.
                    if let grabbed {
                        Task { await grabbed.refocus?() }
                    }
                }
                picker.onDismiss = { [weak self] in
                    // Clicked outside: the click itself already moved focus
                    // wherever the user clicked — do not refocus or edit.
                    self?.finishPickerSession()
                }
                self.pickerController = picker
                self.lowerOwnWindowsForPicker()
                picker.show()
            } catch {
                self.finishPickerSession()
                ErrorPresenter.show(title: "SpellCheck", message: CorrectionEngine.message(for: error))
            }
        }
    }

    /// Tears down the current picker session state completely — exactly one
    /// place, so no path (choose, cancel, outside click, grab failure) can
    /// leave a stale `pickerSessionActive` flag blocking future openings.
    /// When a correction was started, the lowered windows stay lowered until
    /// the run's terminal event (see `handle(_:)`) — restoring them earlier
    /// would let them jump forward while SpellCheck is still active mid-run.
    private func finishPickerSession(startedRun: Bool = false) {
        pickerController = nil
        pendingGrab = nil
        pickerSessionActive = false
        windowsLoweredForRun = startedRun
        if !startedRun {
            endPickerSession()
        }
    }

    private func runPrompt(_ prompt: Prompt, on grabbed: GrabbedText?) {
        guard let engine, let grabbed else { return }
        lastRunInputLength = grabbed.scope.text.utf16.count
        Task { await engine.run(prompt: prompt, on: grabbed) }
    }

    // MARK: Picker session vs. other SpellCheck windows

    /// While the picker is up, SpellCheck must own the keyboard — which means
    /// activating the app. Activation would normally raise ALL of SpellCheck's
    /// visible windows over the user's work; instead, other SpellCheck
    /// windows are temporarily put at a window level below other apps' normal
    /// windows, so they stay put. Keyboard focus is untouched.
    private func lowerOwnWindowsForPicker() {
        let own = [settingsController?.window, promptEditorController?.window]
            .compactMap { $0 }
            .filter { $0.isVisible }
        for window in own {
            window.level = NSWindow.Level(rawValue: -1)
        }
        loweredWindows = own
    }

    private func endPickerSession() {
        for window in loweredWindows {
            window.level = .normal
        }
        loweredWindows = []
    }

    // MARK: Events

    private func handle(_ event: EngineEvent) {
        statusBarController?.handle(event)
        switch event {
        case .working:
            // Circular progress ring near the cursor: fills over the
            // learned response-time estimate for this model + text length.
            workingIndicator?.show(estimatedSeconds: responseTimeEstimator?
                .estimate(model: engine?.modelKey ?? settings.model, inputLength: lastRunInputLength))
        case .succeeded, .failed, .replaceFailed:
            workingIndicator?.hide()
            // Terminal: restore our own windows' level now that the
            // workflow is over (a busy rejection is NOT terminal — the
            // original correction is still running, keep them lowered).
            if windowsLoweredForRun {
                windowsLoweredForRun = false
                endPickerSession()
            }
        case .busy:
            // Another edit was requested while one is running: the ring
            // stays up (the original correction is still in flight) and the
            // rejection is menu-bar-only feedback. Nothing is edited.
            break
        case .idle:
            workingIndicator?.hide()
        case .requestTiming(let model, let seconds, let inputLength):
            // Learn from the finished request so the next ring is accurate.
            responseTimeEstimator?.record(model: model, inputLength: inputLength, seconds: seconds)
        }
        // Real API/configuration/permission errors still alert. Replacement
        // failures (including uncertain readback) and busy rejections stay
        // menu-bar only — the user asked for no intrusive popup there.
        if case .failed(let message) = event {
            ErrorPresenter.show(title: "SpellCheck", message: message)
        }
    }

    // MARK: Windows & menu actions

    func openSettings() {
        settingsController?.showWindow(nil)
        settingsController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPromptEditor() {
        promptEditorController?.showWindow(nil)
        promptEditorController?.window?.orderFrontRegardless()
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
