import Foundation
import Testing
@testable import SpellCheckCore

struct SettingsTests {

    @Test func defaultSettingsAreRuleBasedAndOffline() {
        let settings = Settings.default
        #expect(settings.backend == .ruleBased)
        #expect(settings.apiKey.isEmpty)
        #expect(settings.hotKey.isUsableAsGlobalHotkey)
    }

    @Test func settingsRoundTripThroughJSON() throws {
        var settings = Settings.default
        settings.apiKey = "sk-test"
        settings.backend = .openAICompatible
        settings.customPrompts = [CustomPrompt(name: "Pirate", prompt: "Rewrite as a pirate")]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func backendKindHasStableRawValues() {
        #expect(BackendKind.ruleBased.rawValue == "Offline (rule-based)")
        #expect(BackendKind.openAICompatible.rawValue == "OpenAI-compatible API")
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
        #expect(decoded == Settings.default)
        #expect(decoded.menuBarIconStyle == "omega-check")
    }

    @Test func menuBarIconStyleRoundTripsThroughJSON() throws {
        var settings = Settings.default
        settings.menuBarIconStyle = "spellcheck"
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.menuBarIconStyle == "spellcheck")
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
        #expect(ResponseCleaner.clean("“Hello world”", input: "hello world") == "Hello world")
    }

    @Test func doesNotStripUnbalancedQuotes() {
        #expect(ResponseCleaner.clean("\"Hello world", input: "hello world") == "\"Hello world")
    }

    @Test func preservesInternalLineBreaks() {
        #expect(ResponseCleaner.clean("Line one\nLine two", input: "line one") == "Line one\nLine two")
    }
}
