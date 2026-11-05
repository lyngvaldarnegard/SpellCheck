import Foundation
import Testing
@testable import SpellCheckCore

struct SettingsTests {

    @Test func defaultSettingsUseOptionLAndNoBackendKind() {
        let settings = Settings.default
        #expect(settings.hotKey == .default)
        #expect(settings.hotKey.description == "⌥L")
        #expect(settings.apiKey.isEmpty)
        #expect(settings.prompts.isEmpty)
        #expect(!settings.didSeedDefaultPrompts)
    }

    @Test func settingsRoundTripThroughJSON() throws {
        var settings = Settings.default
        settings.apiKey = "sk-test"
        settings.prompts = [Prompt(name: "Pirate", prompt: "Rewrite as a pirate", icon: PromptIcon.pen.rawValue)]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func menuBarIconStyleDefaultsToOmegaCheck() {
        #expect(Settings.default.menuBarIconStyle == "omega-check")
        #expect(Settings.defaultMenuBarIconStyle == "omega-check")
    }

    @Test func legacySettingsJSONWithoutMenuBarIconStyleStillDecodes() throws {
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings.default)) as? [String: Any] ?? [:]
        dict.removeValue(forKey: "menuBarIconStyle")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded.menuBarIconStyle == "omega-check")
    }

    @Test func menuBarIconStyleRoundTripsThroughJSON() throws {
        var settings = Settings.default
        settings.menuBarIconStyle = "spellcheck"
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.menuBarIconStyle == "spellcheck")
    }

    @Test func v1SettingsFileDecodesAndKeepsUserValues() throws {
        // A settings.json written by v1: backend/showConfirmation/translation
        // language keys that no longer exist, plus legacy custom prompts.
        let json = """
        {
          "hotKey": {"keyCode": 40, "modifiers": 1572864},
          "backend": "OpenAI-compatible API",
          "apiKey": "sk-keep-me",
          "model": "mistral-small-latest",
          "baseURL": "https://api.mistral.ai/v1",
          "customPrompts": [{"id": "11111111-1111-1111-1111-111111111111", "name": "Juss", "prompt": "Polish legal text"}],
          "translationLanguage": "German",
          "launchAtLogin": true,
          "showConfirmation": false,
          "menuBarIconStyle": "omega"
        }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(decoded.apiKey == "sk-keep-me")
        #expect(decoded.model == "mistral-small-latest")
        #expect(decoded.baseURL == "https://api.mistral.ai/v1")
        #expect(decoded.launchAtLogin == true)
        #expect(decoded.menuBarIconStyle == "omega")
        #expect(decoded.prompts.map(\.name) == ["Juss"])
        #expect(decoded.prompts.first?.prompt == "Polish legal text")
        #expect(!decoded.didSeedDefaultPrompts)
    }

    @Test func migrationMovesLegacyHotKeyToOptionLAndSeedsPrompts() throws {
        let json = """
        {
          "hotKey": {"keyCode": 40, "modifiers": 1572864},
          "apiKey": "sk-keep-me",
          "model": "m",
          "baseURL": "https://api.mistral.ai/v1"
        }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        let migrated = decoded.migrated()
        #expect(migrated.hotKey == .default)
        #expect(migrated.apiKey == "sk-keep-me")
        #expect(migrated.prompts.map(\.name) == Prompt.defaultPrompts.map(\.name))
        #expect(migrated.didSeedDefaultPrompts)
    }

    @Test func migrationKeepsUserChosenHotKey() throws {
        var settings = Settings.default
        settings.hotKey = HotKey(keyCode: 1, modifiers: ModifierFlags.command | ModifierFlags.shift)
        settings.didSeedDefaultPrompts = true
        let migrated = settings.migrated()
        #expect(migrated.hotKey == settings.hotKey)
        #expect(migrated == settings)
    }

    @Test func migrationDoesNotReseedAfterUserDeletesAllPrompts() {
        var settings = Settings.default
        settings.didSeedDefaultPrompts = true
        settings.prompts = []
        let migrated = settings.migrated()
        #expect(migrated.prompts.isEmpty)
    }

    @Test func migrationSeedsOnlyOnce() {
        var settings = Settings.default
        settings.prompts = [Prompt(name: "Only mine", prompt: "x")]
        let migrated = settings.migrated()
        #expect(migrated.prompts.map(\.name) == ["Only mine"])
        let again = migrated.migrated()
        #expect(again == migrated)
    }
}

struct ResponseCleanerTests {

    @Test func passesPlainTextThrough() {
        #expect(ResponseCleaner.clean("Hello world", input: "hello world") == "Hello world")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(ResponseCleaner.clean("  Hello world\n", input: "hello world") == "Hello world")
    }

    @Test func stripsOneLayerOfQuotes() {
        #expect(ResponseCleaner.clean("\"Hello world\"", input: "hello world") == "Hello world")
        #expect(ResponseCleaner.clean("\u{201c}Hello world\u{201d}", input: "hello world") == "Hello world")
    }

    @Test func doesNotStripUnbalancedQuotes() {
        #expect(ResponseCleaner.clean("\"Hello world", input: "hello world") == "\"Hello world")
    }

    @Test func preservesInternalLineBreaks() {
        #expect(ResponseCleaner.clean("Line one\nLine two", input: "line one") == "Line one\nLine two")
    }
}
