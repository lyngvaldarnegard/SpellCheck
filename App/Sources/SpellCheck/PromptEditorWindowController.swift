import AppKit
import SwiftUI
import SpellCheckCore

/// FixKey-style Prompt Editor: a dark two-pane window. Left: searchable
/// prompt list (icon, bold title, one-line preview). Right: title field,
/// full prompt text, Delete and Save. Every prompt is an ordinary editable
/// entry. ⌘S and the Save button both persist.
@MainActor
final class PromptEditorWindowController: NSWindowController {

    private let save: @MainActor ([Prompt]) async throws -> Void
    private var prompts: [Prompt]
    private let onPromptsChanged: ([Prompt]) -> Void

    init(prompts: [Prompt],
         save: @escaping @MainActor ([Prompt]) async throws -> Void,
         onPromptsChanged: @escaping ([Prompt]) -> Void) {
        self.prompts = prompts
        self.save = save
        self.onPromptsChanged = onPromptsChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prompt Editor"
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 420)
        super.init(window: window)
        window.contentView = NSHostingView(rootView: PromptEditorView(controller: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var currentPrompts: [Prompt] { prompts }

    /// Keeps the controller's prompt list in sync with the persisted list
    /// (e.g. after a save from Settings).
    func reload(prompts: [Prompt]) {
        self.prompts = prompts
    }

    func persist(_ prompts: [Prompt]) async throws {
        try await save(prompts)
        self.prompts = prompts
        onPromptsChanged(prompts)
    }

    /// Reorders `prompts` by moving the given offsets. Purely structural:
    /// no prompt title, text, icon or other setting is modified.
    func reorder(_ prompts: [Prompt], fromOffsets: IndexSet, toOffset: Int) -> [Prompt] {
        var next = prompts
        next.move(fromOffsets: fromOffsets, toOffset: toOffset)
        return next
    }

    override func showWindow(_ sender: Any?) {
        // Rebuild the hosted view so the editor always shows the CURRENT
        // persisted prompts, never a snapshot from an earlier open.
        window?.contentView = NSHostingView(rootView: PromptEditorView(controller: self))
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PromptEditorView: View {
    let controller: PromptEditorWindowController

    @State private var prompts: [Prompt] = []
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var saveState: SaveState = .idle
    @State private var saveError: String?
    @State private var autosaveTask: Task<Void, Never>?

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    private var filtered: [Prompt] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return prompts }
        return prompts.filter { $0.name.lowercased().contains(query) || $0.prompt.lowercased().contains(query) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var selectedPrompt: Prompt? {
        prompts.first { $0.id == selectedID }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { prompts.first { $0.id == selectedID }?.name ?? "" },
            set: { value in
                if let index = prompts.firstIndex(where: { $0.id == selectedID }) {
                    prompts[index].name = value
                }
            }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { prompts.first { $0.id == selectedID }?.prompt ?? "" },
            set: { value in
                if let index = prompts.firstIndex(where: { $0.id == selectedID }) {
                    prompts[index].prompt = value
                }
            }
        )
    }

    private var iconBinding: Binding<String> {
        Binding(
            get: { prompts.first { $0.id == selectedID }?.icon ?? PromptIcon.check.rawValue },
            set: { value in
                if let index = prompts.firstIndex(where: { $0.id == selectedID }) {
                    prompts[index].icon = value
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            editorPane
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { prompts = controller.currentPrompts }
        // Autosave: every change persists — title, text, icon, add, delete
        // and drag-to-reorder (debounced, so typing does not write to disk
        // per keystroke). ⌘S and the Save button still save immediately.
        .onChange(of: prompts) {
            autosaveTask?.cancel()
            autosaveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await savePrompts()
            }
        }
        .alert("Could not save prompts", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search prompts", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            List(selection: $selectedID) {
                if isSearching {
                    ForEach(filtered) { prompt in
                        PromptRowView(prompt: prompt)
                            .tag(prompt.id)
                            .contentShape(Rectangle())
                    }
                } else {
                    // Bound ForEach + onMove: rows can be dragged up/down to
                    // reorder; the list shows the standard insertion gap while
                    // dragging. The new order persists immediately on drop.
                    ForEach($prompts) { $prompt in
                        PromptRowView(prompt: prompt)
                            .tag(prompt.id)
                            .contentShape(Rectangle())
                    }
                    .onMove { from, to in
                        prompts = controller.reorder(prompts, fromOffsets: from, toOffset: to)
                        Task { await savePrompts() }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if filtered.isEmpty {
                    Text(prompts.isEmpty ? "No prompts yet" : "No prompts match your search")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    let prompt = Prompt(name: "New Prompt", prompt: "", icon: PromptIcon.sparkle.rawValue)
                    prompts.append(prompt)
                    selectedID = prompt.id
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Spacer()
                statusText
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusText: some View {
        Group {
            switch saveState {
            case .saving: Text("Saving…")
            case .saved: Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .idle: Text("\(prompts.count) prompts").foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    // MARK: Editor pane

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedPrompt != nil {
                TextField("Enter prompt title", text: titleBinding)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Icon", selection: iconBinding) {
                    ForEach(PromptIcon.allCases) { icon in
                        Text("\(icon.glyph) \(icon.displayName)").tag(icon.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.headline)
                    TextEditor(text: bodyBinding)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Button(role: .destructive) {
                        if let id = selectedID {
                            prompts.removeAll { $0.id == id }
                            selectedID = prompts.first?.id
                        }
                    } label: {
                        Text("Delete")
                            .frame(width: 80)
                    }
                    .tint(.red)

                    Spacer()

                    Button {
                        Task { await savePrompts() }
                    } label: {
                        Text(saveState == .saving ? "Saving…" : "Save")
                            .frame(width: 80)
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .tint(.green)
                    .disabled(saveState == .saving)
                }
            } else {
                Spacer()
                Text("Select a prompt on the left, or add a new one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            }
        }
        .padding(16)
    }

    private func savePrompts() async {
        saveState = .saving
        do {
            try await controller.persist(prompts)
            saveState = .saved
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if saveState == .saved { saveState = .idle }
        } catch {
            saveState = .idle
            saveError = error.localizedDescription
        }
    }
}


private struct PromptRowView: View {
    let prompt: Prompt

    var body: some View {
        HStack(spacing: 10) {
            Text(prompt.iconKind.glyph)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.green.opacity(0.18))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(prompt.prompt.isEmpty ? "No prompt text yet" : prompt.prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
