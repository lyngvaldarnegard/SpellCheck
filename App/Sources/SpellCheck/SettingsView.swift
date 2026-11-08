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
                ModelWhitelistField(
                    selection: $settings.whitelistedModels,
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    onFetched: { models in controller.purgeUnknownModels?(models) }
                )
                .id("whitelist-\(settings.baseURL)")
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

            Section("Response Times") {
                responseTimes
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
        .onChange(of: settings) { _ in
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

    /// Learned per-model response times, ranked by IQM (fastest first) with
    /// a shared-axis box plot per model (issue #18). All values are seconds
    /// per 100 tokens (4 chars/token).
    @ViewBuilder
    private var responseTimes: some View {
        let stats = controller.responseTimeStats?() ?? []
        if stats.isEmpty {
            Text("No response times learned yet — they are collected automatically as you use the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            // All rows share one horizontal seconds axis: the same seconds
            // value sits at the same horizontal position in every row.
            let axisMax = max(stats.map(\.maximumSeconds).max() ?? 1, 0.1)
            GeometryReader { geo in
                let plotWidth = max(120, geo.size.width - 250)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(stats, id: \.model) { stat in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stat.model)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(stat.sampleCount) samples · IQM \(stat.interQuartileMeanSeconds, format: .number.precision(.fractionLength(1))) s")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 226, alignment: .leading)
                            BoxPlot(stat: stat, axisMax: axisMax, width: plotWidth)
                        }
                    }
                }
            }
            // Explicit height (GeometryReader inside a Form otherwise
            // collapses and the legend below overlaps the last row).
            .frame(height: CGFloat(stats.count) * 64 + 4)
            Text("Box = Q1–Q3 · line = median · whiskers = min–max · red dot = IQM. Seconds per 100 tokens (4 characters per token), from your own requests; ranked fastest first. Nothing is sent anywhere.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

/// One horizontal box plot on a shared seconds axis: whiskers span the
/// observed min–max, the box spans Q1–Q3, the line is the median and the
/// dot marks the inter-quartile mean (the number the ranking and the
/// progress ring use).
private struct BoxPlot: View {
    let stat: ResponseTimeEstimator.ModelStatistics
    let axisMax: Double
    let width: CGFloat

    private func x(_ seconds: Double) -> CGFloat {
        CGFloat(min(max(seconds / axisMax, 0), 1)) * width
    }

    var body: some View {
        let boxTop: CGFloat = 9
        let boxHeight: CGFloat = 14
        let midY = boxTop + boxHeight / 2
        // Named lowX/highX (not min/max) so Swift's max()/min() functions
        // are not shadowed in this scope.
        let lowX = x(stat.minimumSeconds)
        let q1 = x(stat.firstQuartileSeconds)
        let median = x(stat.medianSeconds)
        let q3 = x(stat.thirdQuartileSeconds)
        let highX = x(stat.maximumSeconds)
        let iqm = x(stat.interQuartileMeanSeconds)
        ZStack(alignment: .topLeading) {
            // Whisker: observed min to observed max.
            Path { p in
                p.move(to: CGPoint(x: lowX, y: midY))
                p.addLine(to: CGPoint(x: highX, y: midY))
            }
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            // Box: Q1 to Q3.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.green.opacity(0.25))
                .frame(width: max(q3 - q1, 2), height: boxHeight)
                .offset(x: q1, y: boxTop)
            // Median line.
            Path { p in
                p.move(to: CGPoint(x: median, y: boxTop))
                p.addLine(to: CGPoint(x: median, y: boxTop + boxHeight))
            }
            .stroke(Color.primary, lineWidth: 1.5)
            // IQM marker: RED so it contrasts with the green box and
            // median details, ringed so it never disappears inside the box;
            // its value is printed next to it in the same red.
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.primary.opacity(0.6), lineWidth: 1))
                .offset(x: iqm - 4, y: midY - 4)
            Text(Self.value(stat.interQuartileMeanSeconds))
                .font(.system(size: 9))
                .foregroundStyle(Color.red)
                .offset(x: iqm + 6, y: 0)
            // Numeric labels for min, Q1, median, Q3 and max under the
            // plot. ALL five are always drawn: labels that would collide
            // are staggered onto a second line instead of being skipped.
            ForEach(Self.labelledPositions(lowX: lowX, q1: q1, median: median, q3: q3, highX: highX,
                                           stat: stat), id: \.position) { item in
                Text(item.text)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .offset(x: item.position, y: boxTop + boxHeight + 4 + CGFloat(item.line) * 11)
            }
        }
        .frame(width: width, height: boxTop + boxHeight + 30)
    }

    private static func value(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }

    /// All five labelled elements (min, Q1, median, Q3, max), left to
    /// right. Each label goes on the first of two staggered lines where it
    /// does not collide with the previous label on that line, so Q1 and Q3
    /// are never dropped — close values simply alternate lines.
    private static func labelledPositions(
        lowX: CGFloat, q1: CGFloat, median: CGFloat, q3: CGFloat, highX: CGFloat,
        stat: ResponseTimeEstimator.ModelStatistics
    ) -> [(position: CGFloat, text: String, line: Int)] {
        let all: [(CGFloat, Double)] = [
            (lowX, stat.minimumSeconds),
            (q1, stat.firstQuartileSeconds),
            (median, stat.medianSeconds),
            (q3, stat.thirdQuartileSeconds),
            (highX, stat.maximumSeconds),
        ]
        var lineEnds: [CGFloat] = [-.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        var kept: [(position: CGFloat, text: String, line: Int)] = []
        for (position, seconds) in all.sorted(by: { $0.0 < $1.0 }) {
            var line = 0
            while line < lineEnds.count && position - lineEnds[line] < 26 {
                line += 1
            }
            if line >= lineEnds.count { line = lineEnds.count - 1 }
            lineEnds[line] = position
            kept.append((position, value(seconds), line))
        }
        return kept
    }
}

/// Multi-select model whitelist: the user approves which models are
/// acceptable (quality/cost); the app then automatically serves each request
/// from the fastest whitelisted model (learned response times) and falls
/// through the ranked list on retryable failures. Fetches the provider's
/// model list like the single-model pickers; manual whitelist entries are
/// kept even when they are not in the fetched list.
private struct ModelWhitelistField: View {
    @Binding var selection: [String]
    let apiKey: String
    let baseURL: String
    var onFetched: ([String]) -> Void = { _ in }

    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchError: String?
    /// The fetched list can be huge: collapsed by default, only the
    /// whitelisted models are shown; expand to check more.
    @State private var showAllModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model whitelist (optional)")
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                Spacer()
                Button(isFetching ? "Fetching\u{2026}" : "Fetch models") {
                    fetchModels()
                }
                .disabled(isFetching)
            }
            // Collapsed: only the whitelisted models. Expanded: the whole
            // fetched list (plus whitelisted entries it does not contain).
            let listed = showAllModels
                ? availableModels + selection.filter { !availableModels.contains($0) }
                : selection
            if !listed.isEmpty {
                ForEach(listed, id: \.self) { model in
                    Toggle(model, isOn: Binding(
                        get: { selection.contains(model) },
                        set: { on in
                            if on, !selection.contains(model) { selection.append(model) }
                            else if !on { selection.removeAll { $0 == model } }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .controlSize(.regular)
                }
            }
            if !availableModels.isEmpty {
                Button(showAllModels ? "Show whitelisted only" : "Show all models (\(availableModels.count))") {
                    showAllModels.toggle()
                }
                .controlSize(.small)
            }
            if let fetchError {
                Text(fetchError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if selection.isEmpty {
                Text("Leave empty to always use the Model field above. When enabled, each request uses the fastest whitelisted model based on learned response times; failures fall through to the next fastest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(selection.count) models whitelisted \u{2014} ranked automatically by speed; you control quality and cost.")
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
                    // Purge whitelisted models the provider no longer serves
                    // (the user's rule: never call or keep data for outdated
                    // models), and drop their learned samples too.
                    selection = selection.filter { models.contains($0) }
                    onFetched(models)
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
    /// Supplies the learned per-model response-time statistics for the
    /// Settings section (set by AppDelegate once setup completes).
    var responseTimeStats: (() -> [ResponseTimeEstimator.ModelStatistics])?
    /// Called with the provider's freshly fetched model list so samples for
    /// models the provider no longer serves can be purged (set by
    /// AppDelegate).
    var purgeUnknownModels: (([String]) -> Void)?

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
