import SwiftUI
import SpellCheckCore
import SpellCheckEngine

/// SwiftUI settings window content: API configuration, global shortcut and
/// app behaviour. Prompts live in their own Prompt Editor window.
struct SettingsView: View {
    @State private var settings: AppSettings
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelsError: String?
    @State private var saveState: SaveState = .idle
    @State private var saveError: String?
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
                modelPicker
                Text("All text editing runs through this API. Get a key at your provider's dashboard (e.g. console.mistral.ai).")
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

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if availableModels.isEmpty {
                    TextField("Model (e.g. mistral-small-latest)", text: $settings.model)
                } else {
                    Picker("Model", selection: $settings.model) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        if !availableModels.contains(settings.model) {
                            Text("\(settings.model) (custom)").tag(settings.model)
                        }
                    }
                }
                Button(isFetchingModels ? "Fetching…" : "Fetch models") {
                    fetchModels()
                }
                .disabled(isFetchingModels)
            }
            if let modelsError {
                Text(modelsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !availableModels.isEmpty {
                Text("\(availableModels.count) models available from this API")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyPreset(_ preset: APIProvider) {
        settings.baseURL = preset.baseURL
        settings.model = preset.defaultModel
        availableModels = []
        modelsError = nil
    }

    private func fetchModels() {
        isFetchingModels = true
        modelsError = nil
        let apiKey = settings.apiKey
        let baseURL = settings.baseURL
        Task {
            do {
                let models = try await ModelCatalog.fetchModels(apiKey: apiKey, baseURL: baseURL)
                await MainActor.run {
                    availableModels = models
                    if let first = models.first, !models.contains(settings.model) {
                        settings.model = first
                    }
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    modelsError = CorrectionEngine.message(for: error)
                    isFetchingModels = false
                }
            }
        }
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

    func configureSave(_ save: @escaping @MainActor (AppSettings) async throws -> Void) {
        self.saveViaDelegate = save
    }

    /// Persists the settings, then applies them to the running app. Only
    /// called when saving succeeded — failures propagate to the UI.
    func commit(_ settings: AppSettings) async throws {
        try await saveViaDelegate?(settings)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsWindowGroup<Content: View>: Scene {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some Scene {
        WindowGroup("SpellCheck Settings") {
            content()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
