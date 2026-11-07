import Testing
import SpellCheckCore
@testable import SpellCheck

struct AppWiringTests {

    @Test func defaultSettingsUseOptionLAndEditablePrompts() {
        #expect(Settings.default.hotKey == .default)
        #expect(Settings.default.hotKey.description == "⌥L")
        #expect(Settings.default.hotKey.isUsableAsGlobalHotkey)
    }

    @Test func optionLIsAValidGlobalShortcut() {
        let optionL = HotKey(keyCode: 37, modifiers: ModifierFlags.option)
        #expect(optionL.isUsableAsGlobalHotkey)
        #expect(optionL.description == "⌥L")
    }

    @Test func defaultPromptsAreEditableDataNotHardcodedActions() {
        for prompt in Prompt.defaultPrompts {
            #expect(!prompt.name.isEmpty)
            #expect(!prompt.prompt.isEmpty)
        }
        #expect(Prompt.defaultPrompts.contains { $0.name == "Fix Grammar" })
    }

    @Test func migrationSeedsPromptsAndMovesLegacyHotKey() {
        var settings = Settings.default
        settings.hotKey = .legacyDefault
        let migrated = settings.migrated()
        #expect(migrated.hotKey == .default)
        #expect(migrated.prompts.map(\.name) == Prompt.defaultPrompts.map(\.name))
        #expect(migrated.didSeedDefaultPrompts)
    }

    @Test func providerPresetsKeepBaseURLAndModelConsistent() {
        #expect(APIProvider.mistral.defaultModel == "mistral-small-latest")
        #expect(APIProvider.deepSeek.defaultModel.hasPrefix("deepseek"))
        for provider in APIProvider.allCases {
            #expect(APIProvider.matching(baseURL: provider.baseURL) == provider)
        }
    }
}

@MainActor
struct StatusBarEventTests {

    /// The menu-bar icon is just the icon: engine events must not change it
    /// (no status glyphs, no tooltips — the cursor spinner is the sole
    /// indicator, and the user asked for no status reporting here).
    @Test func engineEventsDoNotChangeTheIcon() {
        let controller = StatusBarController(settings: .default)
        let iconBefore = controller.statusIconForTesting
        controller.handle(.working("Running…"))
        controller.handle(.busy("A correction is still running"))
        controller.handle(.replaceFailed("selection gone"))
        controller.handle(.succeeded("done"))
        controller.handle(.failed("api error"))
        controller.handle(.idle)
        #expect(controller.statusIconForTesting == iconBefore)
        #expect(controller.toolTipForTesting == nil)
    }
}

@MainActor
struct WorkingIndicatorTests {

    /// The circular progress ring: visible while working, hidden when done,
    /// never key, never intercepting mouse clicks.
    @Test func ringShowsAndHidesWithoutTakingFocus() {
        let indicator = WorkingIndicatorController()
        #expect(indicator.isShowing == false)
        indicator.show(estimatedSeconds: nil)
        #expect(indicator.isShowing == true)
        indicator.hide()
        #expect(indicator.isShowing == false)
    }

    @Test func ringRestartsOnlyWhenNotAlreadyShowing() {
        let indicator = WorkingIndicatorController()
        indicator.show(estimatedSeconds: 5)
        // A second `.working` event of the same run must not restart the
        // animation mid-revolution (only reposition).
        indicator.show(estimatedSeconds: 5)
        #expect(indicator.isShowing == true)
        indicator.hide()
        indicator.show(estimatedSeconds: 2)
        #expect(indicator.isShowing == true)
    }
}
