import SwiftUI
import SpellCheckCore
import SpellCheckEngine

/// SwiftUI settings window content. All state lives in the engine's
/// `SettingsStore`; changes are committed through `onChange`.
struct SettingsView: View {
    @State private var settings: AppSettings
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelsError: String?
    private let controller: SettingsWindowController

    init(controller: SettingsWindowController) {
        self.controller = controller
        _settings = State(initialValue: controller.initialSettings)
    }

    var body: some View {
        Form {
            Section("Correction") {
                Picker("Backend", selection: $settings.backend) {
                    ForEach(BackendKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                if settings.backend == .openAICompatible {
                    providerPresets
                    SecureField("API Key", text: $settings.apiKey)
                        .textContentType(.password)
                    TextField("API Base URL", text: $settings.baseURL)
                    modelPicker
                }
            }

            Section("Hot Key") {
                HotKeyRecorderView(hotKey: $settings.hotKey)
            }

            Section("Behaviour") {
                Toggle("Show confirmation before replacing", isOn: $settings.showConfirmation)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                LabeledContent("Translation language") {
                    TextField("Language", text: $settings.translationLanguage)
                        .frame(width: 140)
                }
            }

            Section("Custom Prompts") {
                ForEach($settings.customPrompts) { $prompt in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $prompt.name)
                        TextField("Prompt", text: $prompt.prompt)
                    }
                }
                Button("Add Prompt") {
                    settings.customPrompts.append(CustomPrompt(name: "New Prompt", prompt: ""))
                }
                .disabled(settings.customPrompts.count >= 10)
            }

            Section {
                HStack {
                    Text("SpellCheck works in every app. Select text or place the caret in a sentence, then press the hot key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { controller.commit(settings) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 480)
    }

    private var providerPresets: some View {
        HStack(spacing: 8) {
            Text("Provider")
            Spacer()
            ForEach(APIProviderPreset.allCases) { preset in
                Button(preset.label) {
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
                    TextField("Model (e.g. deepseek-chat)", text: $settings.model)
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

    private func applyPreset(_ preset: APIProviderPreset) {
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
}

private enum APIProviderPreset: String, CaseIterable, Identifiable {
    case mistral = "Mistral"
    case openAI = "OpenAI"
    case deepSeek = "DeepSeek"
    case openRouter = "OpenRouter"
    case ollama = "Ollama (local)"

    var id: String { rawValue }

    var label: String { rawValue }

    var baseURL: String {
        switch self {
        case .mistral: return "https://api.mistral.ai/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .mistral: return "mistral-small-latest"
        case .openAI: return "gpt-4o-mini"
        case .deepSeek: return "deepseek-chat"
        case .openRouter: return "mistralai/mistral-small-latest"
        case .ollama: return "llama3.2"
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
    private let store: SettingsStore?
    var initialSettings: AppSettings
    private let onChange: (AppSettings) -> Void

    init(store: SettingsStore?, settings: AppSettings, onChange: @escaping (AppSettings) -> Void) {
        self.store = store
        self.initialSettings = settings
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpellCheck Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(controller: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func commit(_ settings: AppSettings) {
        let snapshot = settings
        if let store {
            Task {
                try? await store.update { _ in snapshot }
            }
        }
        onChange(settings)
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
