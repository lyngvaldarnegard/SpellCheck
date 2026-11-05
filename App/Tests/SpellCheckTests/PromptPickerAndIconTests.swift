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

    @Test func borderlessPanelCanBecomeKey() async throws {
        _ = makeApp()
        let controller = PromptPickerWindowController(prompts: [Prompt(name: "Fix", prompt: "fix it")])
        controller.show()
        // A plain borderless NSPanel refuses key status — the picker panel
        // overrides canBecomeKey, which is what v0.2.2 was missing. Give the
        // asynchronous activation a moment to settle before asserting.
        for _ in 0..<20 where !controller.isPanelKeyWindow {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(controller.isPanelKeyWindow)
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

/// Menu-bar icon assets: the chosen style must load a template image, and the
/// shipped asset must be the vector PDF (Retina-sharp), not just the 22px PNG
/// that caused the blurry look in v0.2.2.
@MainActor
struct MenuBarIconTests {

    @Test func allFourStylesLoadTemplateImages() {
        for style in MenuBarIconStyle.allCases {
            let image = style.templateImage
            #expect(image != nil, "missing template image for \(style.rawValue)")
            #expect(image?.isTemplate == true, "\(style.rawValue) must be a template image")
            #expect(image?.size.width ?? 0 > 8, "\(style.rawValue) has no usable size")
        }
    }

    @Test func preferredAssetIsVectorPDF() {
        for style in MenuBarIconStyle.allCases {
            let pdf = Bundle.main.path(forResource: style.rawValue, ofType: "pdf", inDirectory: "MenuBarIcons")
            #expect(pdf != nil, "missing vector PDF asset for \(style.rawValue)")
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
