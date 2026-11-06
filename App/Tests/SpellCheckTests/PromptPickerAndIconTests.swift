import Testing
import AppKit
import SpellCheckCore
@testable import SpellCheck

/// Focus and keyboard behavior of the prompt picker. The v0.2.2 bug was that
/// keystrokes reached the ORIGINAL app (Enter replaced the selection with a
/// line break) because the borderless panel never became the key window of an
/// active app. These tests exercise the real AppKit focus chain as far as a
/// headless CI session allows.
@MainActor
struct PromptPickerFocusTests {

    private func makeApp() -> NSApplication {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        return app
    }

    private func keyEvent(_ keyCode: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @Test func borderlessPanelCanBecomeKeyAndOwnsKeyboardWhenActive() async throws {
        _ = makeApp()
        let controller = PromptPickerWindowController(prompts: [Prompt(name: "Fix", prompt: "fix it")])
        controller.show()
        // A plain borderless NSPanel refuses key status — the picker panel
        // overrides canBecomeKey, which is what v0.2.2 was missing.
        #expect(controller.panelCanBecomeKeyForTesting)
        // Give the asynchronous activation a moment to settle.
        for _ in 0..<20 where !controller.isPanelKeyWindow {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // In a real GUI session the app activates and the panel MUST be the
        // key window (that is the whole v0.2.2 fix). A bare test process that
        // was never launched through NSApplication.run() can refuse
        // activation entirely — only tolerate that case.
        if NSApp.isActive {
            #expect(controller.isPanelKeyWindow)
        }
        controller.closeForTesting()
    }

    @Test func searchFieldIsFirstResponderAfterShow() {
        _ = makeApp()
        let controller = PromptPickerWindowController(prompts: [Prompt(name: "Fix", prompt: "fix it")])
        controller.show()
        #expect(controller.firstResponderIsSearchField)
        controller.closeForTesting()
    }

    @Test func enterRunsHighlightedPromptThroughTheKeyWindow() async throws {
        _ = makeApp()
        let controller = PromptPickerWindowController(
            prompts: [Prompt(name: "Fix Grammar", prompt: "polish"), Prompt(name: "Shorter", prompt: "shorten")]
        )
        var chosen: Prompt?
        controller.onChoose = { chosen = $0 }
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)

        // Route a real keyDown through the panel's event queue — this is the
        // path the OS takes when the panel is the key window.
        controller.sendKeyEventForTesting(keyEvent(36, characters: "\r"))
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(chosen?.name == "Fix Grammar")
        controller.closeForTesting()
    }

    @Test func escapeCancelsWithoutChoosing() async throws {
        _ = makeApp()
        let controller = PromptPickerWindowController(prompts: [Prompt(name: "Fix", prompt: "fix it")])
        var chosen: Prompt?
        var cancelled = false
        controller.onChoose = { chosen = $0 }
        controller.onCancel = { cancelled = true }
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)

        controller.sendKeyEventForTesting(keyEvent(53, characters: "\u{1b}"))
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(chosen == nil)
        #expect(cancelled)
        controller.closeForTesting()
    }

    @Test func arrowKeysMoveSelectionAndSearchFilters() {
        _ = makeApp()
        let prompts = (1...5).map { Prompt(name: "Prompt \($0)", prompt: "p\($0)") }
        let controller = PromptPickerWindowController(prompts: prompts)
        controller.show()
        // Down/Up through the same doCommandBy path the field editor uses.
        controller.moveSelectionForTesting(1)
        controller.moveSelectionForTesting(1)
        controller.moveSelectionForTesting(-1)
        #expect(controller.selectedPromptNameForTesting() == "Prompt 2")
        controller.searchForTesting("3")
        #expect(controller.selectedPromptNameForTesting() == "Prompt 3")
        controller.searchForTesting("no match")
        #expect(controller.selectedPromptNameForTesting() == nil)
        controller.closeForTesting()
    }
}

@MainActor
extension PromptPickerWindowController {
    func closeForTesting() {
        closeForTestingInternal()
    }

    func sendKeyEventForTesting(_ event: NSEvent) {
        sendEventForTesting(event)
    }

    func moveSelectionForTesting(_ delta: Int) {
        moveSelectionForTestingInternal(delta)
    }

    func selectedPromptNameForTesting() -> String? {
        selectedPromptNameForTestingInternal()
    }

    func searchForTesting(_ text: String) {
        searchForTestingInternal(text)
    }
}

/// Outside-click dismissal (issue #15): the picker is a transient popup.
/// Clicking outside must dismiss it without choosing a prompt and without
/// invoking the cancel path (which refocuses the original app — the click
/// itself already moved focus).
@MainActor
struct PromptPickerOutsideClickTests {

    private func makeApp() -> NSApplication {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        return app
    }

    @Test func outsideClickDismissesWithoutChoosingAndWithoutRefocus() async throws {
        _ = makeApp()
        let controller = PromptPickerWindowController(prompts: [Prompt(name: "Fix", prompt: "fix it")])
        var chosen: Prompt?
        var cancelled = false
        var dismissed = false
        controller.onChoose = { chosen = $0 }
        controller.onCancel = { cancelled = true }
        controller.onDismiss = { dismissed = true }
        controller.show()
        try await Task.sleep(nanoseconds: 200_000_000)

        controller.dismissFromOutsideClickForTesting()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(chosen == nil)
        #expect(!cancelled)
        #expect(dismissed)
    }

    @Test func pointsOutsidePanelFrameAreDetected() {
        _ = makeApp()
        let controller = PromptPickerWindowController(prompts: [Prompt(name: "Fix", prompt: "fix it")])
        controller.show()
        // The panel is centered by positionPanel(); its own frame is inside,
        // a far-away point is outside.
        let frame = controller.panelFrameForTesting
        #expect(!frame.isEmpty)
        #expect(!controller.isPointOutsidePanelForTesting(NSPoint(x: frame.midX, y: frame.midY)))
        #expect(controller.isPointOutsidePanelForTesting(NSPoint(x: -10000, y: -10000)))
        controller.closeForTesting()
    }
}

/// Menu-bar icon assets. SwiftPM tests do not run inside the packaged .app,
/// so asset LOADING is asserted on the source tree (the files build-app.sh
/// copies into the bundle); verify-bundle.sh asserts the packaged app
/// actually contains them.
@MainActor
struct MenuBarIconTests {

    private static let resourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/SpellCheckTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // App
        .appendingPathComponent("Resources/MenuBarIcons")

    @Test func allFourStylesHaveVectorPDFSources() throws {
        for style in MenuBarIconStyle.allCases {
            let pdf = Self.resourcesRoot.appendingPathComponent("\(style.rawValue).pdf")
            #expect(FileManager.default.fileExists(atPath: pdf.path), "missing vector PDF asset for \(style.rawValue)")
        }
    }

    @Test func allFourStylesHaveSVGArtworkAndPNGFallbacks() throws {
        for style in MenuBarIconStyle.allCases {
            let names = [
                "svg/\(style.rawValue).svg",
                "\(style.rawValue).png",
                "\(style.rawValue)@2x.png",
            ]
            for name in names {
                let url = Self.resourcesRoot.appendingPathComponent(name)
                #expect(FileManager.default.fileExists(atPath: url.path), "missing \(name)")
            }
        }
    }

    @Test func vectorPDFsAreWellFormed() throws {
        for style in MenuBarIconStyle.allCases {
            let data = try Data(contentsOf: Self.resourcesRoot.appendingPathComponent("\(style.rawValue).pdf"))
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.hasPrefix("%PDF-"), "\(style.rawValue).pdf is not a PDF")
            #expect(text.contains("/MediaBox [0 0 18 18]"), "\(style.rawValue).pdf has the wrong page size")
            #expect(text.contains("%%EOF"), "\(style.rawValue).pdf is truncated")
        }
    }

    @Test func iconChoiceSurvivesSettingsRoundTrip() {
        var settings = Settings.default
        settings.menuBarIconStyle = MenuBarIconStyle.spellcheck.rawValue
        let data = try! JSONEncoder().encode(settings)
        let decoded = try! JSONDecoder().decode(Settings.self, from: data)
        #expect(MenuBarIconStyle.from(settingsValue: decoded.menuBarIconStyle) == .spellcheck)
    }
}

/// Prompt reordering in the Prompt Editor and the picker's use of the order.
@MainActor
struct PromptOrderTests {

    @Test func pickerOpensOnFirstPromptInPersistedOrder() {
        _ = NSApplication.shared
        let prompts = [
            Prompt(name: "First", prompt: "1"),
            Prompt(name: "Second", prompt: "2"),
            Prompt(name: "Third", prompt: "3"),
        ]
        let controller = PromptPickerWindowController(prompts: prompts)
        controller.show()
        #expect(controller.selectedPromptNameForTesting() == "First")
        controller.closeForTesting()
    }

    @Test func reorderMovesPromptWithoutAlteringData() {
        let controller = PromptEditorWindowController(
            prompts: [
                Prompt(name: "A", prompt: "a", icon: PromptIcon.pen.rawValue),
                Prompt(name: "B", prompt: "b", icon: PromptIcon.check.rawValue),
                Prompt(name: "C", prompt: "c", icon: PromptIcon.bolt.rawValue),
            ],
            save: { _ in },
            onPromptsChanged: { _ in }
        )
        let original = controller.currentPrompts
        let moved = controller.reorder(original, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(moved.map(\.name) == ["B", "C", "A"])
        // Purely structural: same prompts, same data, different positions.
        #expect(Set(moved) == Set(original))
        #expect(moved.first { $0.name == "A" }?.prompt == "a")
        #expect(moved.first { $0.name == "A" }?.icon == PromptIcon.pen.rawValue)
        let movedDown = controller.reorder(moved, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(movedDown.map(\.name) == ["A", "B", "C"])
    }

    @Test func reorderPersistsThroughTheSavePath() async throws {
        var saved: [Prompt] = []
        let controller = PromptEditorWindowController(
            prompts: [
                Prompt(name: "A", prompt: "a"),
                Prompt(name: "B", prompt: "b"),
            ],
            save: { saved = $0 },
            onPromptsChanged: { _ in }
        )
        let reordered = controller.reorder(controller.currentPrompts, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        try await controller.persist(reordered)
        #expect(saved.map(\.name) == ["B", "A"])
        #expect(controller.currentPrompts.map(\.name) == ["B", "A"])
    }
}
