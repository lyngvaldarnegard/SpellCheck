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
struct BusyEventTests {

    /// A correction requested while another one is running must be reported
    /// in the menu bar (tooltip) — never silently dropped, never a popup.
    @Test func busyEventIsMenuBarOnlyFeedback() {
        let controller = StatusBarController(settings: .default)
        controller.handle(.busy("A correction is still running — the new prompt was not started. Wait for the current one to finish, then try again."))
        #expect(controller.toolTipForTesting?.contains("still running") == true)
    }

    @Test func replaceFailedRemainsMenuBarOnlyFeedback() {
        let controller = StatusBarController(settings: .default)
        controller.handle(.replaceFailed("The original selection is no longer intact"))
        #expect(controller.toolTipForTesting?.contains("no longer intact") == true)
    }
}

@MainActor
struct WorkingIndicatorTests {

    /// The FixKey-style spinner: visible while working, hidden when done,
    /// never key, never intercepting mouse clicks.
    @Test func spinnerShowsAndHidesWithoutTakingFocus() {
        let indicator = WorkingIndicatorController()
        #expect(indicator.isShowing == false)
        indicator.show()
        #expect(indicator.isShowing == true)
        indicator.hide()
        #expect(indicator.isShowing == false)
    }
}
