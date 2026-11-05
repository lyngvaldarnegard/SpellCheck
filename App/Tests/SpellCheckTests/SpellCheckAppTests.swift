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
