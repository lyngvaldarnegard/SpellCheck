import SwiftUI
import SpellCheckCore
import SpellCheckEngine

/// SwiftUI settings window content. All state lives in the engine's
/// `SettingsStore`; changes are committed through `onChange`.
struct SettingsView: View {
    @State private var settings: Settings
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
                    SecureField("API Key", text: $settings.apiKey)
                    TextField("Model", text: $settings.model)
                    TextField("API Base URL", text: $settings.baseURL)
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
        .onChange(of: settings) { _, newValue in
            controller.draft = newValue
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
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            onRecord?(UInt32(event.keyCode), modifiers)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowController {
    private let store: SettingsStore?
    var initialSettings: Settings
    var draft: Settings
    private let onChange: (Settings) -> Void

    init(store: SettingsStore?, settings: Settings, onChange: @escaping (Settings) -> Void) {
        self.store = store
        self.initialSettings = settings
        self.draft = settings
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

    func commit(_ settings: Settings) {
        draft = settings
        if let store {
            Task {
                try? await store.update { $0 = settings }
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
