import SwiftUI
import SpellCheckCore
import SpellCheckEngine

/// SwiftUI settings window content: API configuration, global shortcut and
/// app behaviour. Prompts live in their own Prompt Editor window.
struct SettingsView: View {
    @State private var settings: AppSettings
    @State private var saveState: SaveState = .idle
    @State private var saveError: String?
    @State private var autosaveTask: Task<Void, Never>?
    private let controller: SettingsWindowController

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    init(controller: SettingsWindowController) {
        self.controller = controller
        _settings = State(initialValue: controller.initialSettings)
    }

    var body: some View {
        Form {
            Section("API") {
                providerPresets
                SecureField("API Key", text: $settings.apiKey)
                    .textContentType(.password)
                TextField("API Base URL", text: $settings.baseURL)
                ModelPickerField(
                    label: "Model",
                    placeholder: "Model (e.g. mistral-small-latest)",
                    selection: $settings.model,
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    autoSelectFirstWhenUnlisted: true
                )
                .id("primary-\(settings.baseURL)")
                ModelPickerField(
                    label: "Backup model (optional)",
                    placeholder: "Backup model (e.g. mistral-small-latest)",
                    selection: $settings.backupModel,
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    autoSelectFirstWhenUnlisted: false
                )
                .id("backup-\(settings.baseURL)")
                Text("If a request to the primary model fails temporarily (capacity, rate limit, server error) or returns an unusable response, the same request is retried once with the backup model. Leave empty to disable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("All text editing runs through this API. Get a key at your provider's dashboard (e.g. console.mistral.ai).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Shared Prompt") {
                TextEditor(text: $settings.sharedPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                Text("Included in every request, before the selected prompt. The default asks the model to return only the requested result, in the original language, without explanations or unsolicited formatting. Edit freely — changes apply when you save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Global Shortcut") {
                HotKeyRecorderView(hotKey: $settings.hotKey)
                Text("Opens the prompt picker over the current selection. Any combination works — Option-only combos like ⌥L are fine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar Icon") {
                Picker("Icon", selection: $settings.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        if let image = style.templateImage {
                            HStack(spacing: 6) {
                                Image(nsImage: image)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text(style.displayName)
                            }
                            .tag(style.rawValue)
                        } else {
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                }
                Text("The icon is applied when you save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section {
                HStack {
                    switch saveState {
                    case .saving:
                        Text("Saving…").foregroundStyle(.secondary)
                    case .saved:
                        Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .idle:
                        Text("")
                    }
                    Spacer()
                    Button("Save") {
                        Task { await saveSettings() }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(saveState == .saving)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 480)
        // Autosave: every change persists (debounced, so typing does not
        // write to disk per keystroke). ⌘S and the Save button still save
        // immediately.
        .onChange(of: settings) {
            autosaveTask?.cancel()
            autosaveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await saveSettings()
            }
        }
        .alert("Could not save settings", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var providerPresets: some View {
        HStack(spacing: 8) {
            Text("Provider")
            Spacer()
            ForEach(APIProvider.allCases) { preset in
                Button(preset.displayName) {
                    applyPreset(preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func applyPreset(_ preset: APIProvider) {
        settings.baseURL = preset.baseURL
        settings.model = preset.defaultModel
    }

    private func saveSettings() async {
        saveState = .saving
        do {
            try await controller.commit(settings)
            saveState = .saved
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if saveState == .saved { saveState = .idle }
        } catch {
            saveState = .idle
            saveError = error.localizedDescription
        }
    }
}

/// One model field with the full "Fetch models" experience: fetches the
/// provider's model list (`GET {base}/models`), shows a picker once fetched,
/// and always keeps manual entry available (when the list has not been
/// fetched, or for a model the list does not contain).
///
/// Used for BOTH the primary and the backup model, so the backup gets the
/// same fetch/select workflow as the primary. Fetching never overwrites the
/// user's saved model unless `autoSelectFirstWhenUnlisted` is set (primary
/// keeps its long-standing behavior; the backup never auto-changes).
private struct ModelPickerField: View {
    let label: String
    let placeholder: String
    @Binding var selection: String
    let apiKey: String
    let baseURL: String
    let autoSelectFirstWhenUnlisted: Bool

    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if availableModels.isEmpty {
                    TextField(placeholder, text: $selection)
                } else {
                    Picker(label, selection: $selection) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        if !selection.isEmpty && !availableModels.contains(selection) {
                            Text("\(selection) (custom)").tag(selection)
                        }
                    }
                }
                Button(isFetching ? "Fetching…" : "Fetch models") {
                    fetchModels()
                }
                .disabled(isFetching)
            }
            if let fetchError {
                Text(fetchError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !availableModels.isEmpty {
                Text("\(availableModels.count) models available from this API")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fetchModels() {
        isFetching = true
        fetchError = nil
        let apiKey = apiKey
        let baseURL = baseURL
        Task {
            do {
                let models = try await ModelCatalog.fetchModels(apiKey: apiKey, baseURL: baseURL)
                await MainActor.run {
                    availableModels = models
                    if autoSelectFirstWhenUnlisted, let first = models.first,
                       !models.contains(selection) {
                        selection = first
                    }
                    isFetching = false
                }
            } catch {
                await MainActor.run {
                    fetchError = CorrectionEngine.message(for: error)
                    isFetching = false
                }
            }
        }
    }
}

/// Records a global hot key by listening for the next key-down with modifiers.
struct HotKeyRecorderView: View {
    @Binding var hotKey: HotKey
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(isRecording ? "Press a shortcut…" : hotKey.description)
                .frame(width: 120, alignment: .leading)
            Button(isRecording ? "Cancel" : "Change…") {
                isRecording.toggle()
            }
            if hotKey.isSet {
                Button("Clear") {
                    hotKey = .none
                    isRecording = false
                }
            }
            Spacer()
            if isRecording {
                Text("Press Esc to cancel")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .background(
            HotKeyRecorderRepresentable(isRecording: $isRecording, hotKey: $hotKey)
                .frame(width: 0, height: 0)
        )
    }
}

private struct HotKeyRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotKey: HotKey

    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.onRecord = { keyCode, modifiers in
            hotKey = HotKey(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RecorderView)?.isRecording = isRecording
    }

    private final class RecorderView: NSView {
        var isRecording = false {
            didSet {
                if isRecording, let window {
                    window.makeFirstResponder(self)
                }
            }
        }
        var onRecord: ((UInt32, UInt32) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            guard event.keyCode != 53 /* esc */ else {
                onRecord?(0, 0)
                return
            }
            let modifiers = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            onRecord?(UInt32(event.keyCode), modifiers)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    var initialSettings: AppSettings
    private var saveViaDelegate: (@MainActor (AppSettings) async throws -> Void)?

    init(settings: AppSettings) {
        self.initialSettings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpellCheck Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(controller: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Keeps the snapshot shown in the window in sync with the persisted
    /// settings (e.g. after a save from the Prompt Editor).
    func reload(settings: AppSettings) {
        self.initialSettings = settings
    }

    func configureSave(_ save: @escaping @MainActor (AppSettings) async throws -> Void) {
        self.saveViaDelegate = save
    }

    /// Persists the settings, then applies them to the running app. Only
    /// called when saving succeeded — failures propagate to the UI.
    func commit(_ settings: AppSettings) async throws {
        try await saveViaDelegate?(settings)
    }

    override func showWindow(_ sender: Any?) {
        // Rebuild the hosted view so Settings always shows the CURRENT
        // persisted values, never a snapshot from an earlier open.
        window?.contentView = NSHostingView(rootView: SettingsView(controller: self))
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The app keeps no SwiftUI window scene: Settings and Prompt Editor are
/// manually managed NSWindowControllers (see SpellCheckApp). A SwiftUI
/// WindowGroup produced the stray "Loading…" window that macOS state
/// restoration could raise (and switch Spaces) when the app activated for the
/// picker — so there is no window scene at all anymore.
