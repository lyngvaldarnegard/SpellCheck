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

    // MARK: Shared prompt + backup model (issues #9, #10)

    @Test func defaultSharedPromptAsksForResultOnlyInOriginalLanguage() {
        let shared = Settings.defaultSharedPrompt
        #expect(shared.contains("original language"))
        #expect(shared.contains("translation"))
        #expect(shared.lowercased().contains("only the finished text"))
        #expect(Settings.default.sharedPrompt == shared)
        #expect(Settings.default.backupModel.isEmpty)
    }

    @Test func sharedPromptAndBackupModelRoundTripThroughJSON() throws {
        var settings = Settings.default
        settings.apiKey = "sk-test"
        settings.sharedPrompt = "Svar alltid på norsk."
        settings.backupModel = "mistral-small-latest"
        settings.prompts = [Prompt(name: "Pirate", prompt: "Rewrite as a pirate")]
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.sharedPrompt == "Svar alltid på norsk.")
        #expect(decoded.backupModel == "mistral-small-latest")
        #expect(decoded.prompts.first?.name == "Pirate")
    }

    @Test func settingsFileWithoutSharedPromptKeyGetsEditableDefault() throws {
        // A settings.json written by a version before the shared prompt existed.
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings.default)) as? [String: Any] ?? [:]
        dict.removeValue(forKey: "sharedPrompt")
        dict.removeValue(forKey: "backupModel")
        dict["apiKey"] = "sk-keep-me"
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded.sharedPrompt == Settings.defaultSharedPrompt)
        #expect(decoded.backupModel.isEmpty)
        #expect(decoded.apiKey == "sk-keep-me")
    }

    @Test func editedSharedPromptSurvivesMigration() throws {
        var settings = Settings.default
        settings.sharedPrompt = "Always keep legal terms in full."
        settings.backupModel = "mistral-small-latest"
        let migrated = settings.migrated()
        #expect(migrated.sharedPrompt == "Always keep legal terms in full.")
        #expect(migrated.backupModel == "mistral-small-latest")
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(migrated))
        #expect(decoded.sharedPrompt == "Always keep legal terms in full.")
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
        settings.importedDefaultPromptsVersion = Settings.defaultPromptsVersion
        let migrated = settings.migrated()
        #expect(migrated.hotKey == settings.hotKey)
        #expect(migrated == settings)
    }

    @Test func appUpdateImportsMissingDefaultsOnceAfterUserDeletesAllPrompts() {
        // An app update imports default prompts the user's list is missing —
        // once. After that, deliberate deletions stay deleted.
        var settings = Settings.default
        settings.didSeedDefaultPrompts = true
        settings.prompts = []
        let migrated = settings.migrated()
        #expect(migrated.prompts.map(\.name) == Prompt.defaultPrompts.map(\.name))
        // Deleting them again must NOT re-import on the next launch.
        var deleted = migrated
        deleted.prompts = []
        let again = deleted.migrated()
        #expect(again.prompts.isEmpty)
    }

    @Test func lossyPromptDecodingKeepsHealthyEntries() throws {
        // One malformed prompt entry must not wipe the whole list.
        let json = """
        {
          "apiKey": "sk-keep-me",
          "prompts": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "Allvit", "prompt": "Rettsnavn i fullt \u{2014} «skatteloven»", "icon": "pen"},
            "not-a-prompt",
            {"id": "22222222-2222-2222-2222-222222222222", "name": "Juss", "prompt": "Polish legal text", "icon": "question"},
            {"bogus": true}
          ]
        }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(decoded.apiKey == "sk-keep-me")
        #expect(decoded.prompts.map(\.name) == ["Allvit", "Juss"])
        #expect(decoded.prompts[0].prompt.contains("«skatteloven»"))
    }

    @Test func promptsWithUnknownIconStillDecode() throws {
        let json = """
        {
          "prompts": [
            {"id": "33333333-3333-3333-3333-333333333333", "name": "Future icon", "prompt": "x", "icon": "some-future-glyph"},
            {"id": "44444444-4444-4444-4444-444444444444", "name": "Missing icon", "prompt": "y"}
          ]
        }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(decoded.prompts.map(\.name) == ["Future icon", "Missing icon"])
        #expect(decoded.prompts[0].iconKind == .check)
    }

    @Test func migratedSettingsKeepUserPromptsVerbatim() throws {
        // A v0.2.x settings file with user prompts, re-loaded and migrated by a
        // newer version: titles, full text and properties must be identical.
        var existing = Settings.default
        existing.apiKey = "sk-keep-me"
        existing.didSeedDefaultPrompts = true
        existing.prompts = [
            Prompt(name: "Allvit", prompt: "Skriv retts- og lovnavn i fullt, «skatteloven» i stedet for «sktl.». Behold FSFIN forkortet. \u{00C6}\u{00F8}\u{00E5}", icon: PromptIcon.pen.rawValue),
            Prompt(name: "Napoloen", prompt: "", icon: PromptIcon.sparkle.rawValue),
        ]
        let data = try JSONEncoder().encode(existing)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        let migrated = decoded.migrated()
        // The user's own prompts stay verbatim and FIRST in the list; only
        // defaults with titles the list is missing are appended after them.
        #expect(Array(migrated.prompts.prefix(2)) == existing.prompts)
        #expect(migrated.prompts.count > 2)
        #expect(migrated.apiKey == "sk-keep-me")
        #expect(migrated.didSeedDefaultPrompts)
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(migrated)).migrated()
        #expect(again == migrated)
    }

    @Test func appUpdateNeverReplacesSameTitledUserPrompts() {
        // A user-edited "Fix Grammar" keeps its text; the update only adds
        // titles that are missing entirely.
        var settings = Settings.default
        settings.didSeedDefaultPrompts = true
        let custom = Prompt(name: "Fix Grammar", prompt: "MY CUSTOM TEXT", icon: PromptIcon.pen.rawValue)
        settings.prompts = [custom]
        let migrated = settings.migrated()
        #expect(migrated.prompts.first == custom)
        #expect(migrated.prompts.contains { $0.name == "Fix Grammar" && $0.prompt == "MY CUSTOM TEXT" })
        #expect(migrated.prompts.contains { $0.name == "Humanize" })
        #expect(migrated.prompts.filter { $0.name == "Fix Grammar" }.count == 1)
    }

    @Test func promptOrderRoundTripsAndSurvivesMigration() throws {
        var settings = Settings.default
        settings.didSeedDefaultPrompts = true
        settings.prompts = [
            Prompt(name: "First", prompt: "1", icon: PromptIcon.pen.rawValue),
            Prompt(name: "Second", prompt: "2", icon: PromptIcon.check.rawValue),
            Prompt(name: "Third", prompt: "3", icon: PromptIcon.sparkle.rawValue),
        ]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded.prompts.map(\.name) == ["First", "Second", "Third"])
        let migrated = decoded.migrated()
        // User order is preserved at the FRONT; missing defaults are appended
        // after the user's own prompts, never interleaved or replacing them.
        #expect(Array(migrated.prompts.map(\.name).prefix(3)) == ["First", "Second", "Third"])
        #expect(migrated.prompts.map(\.icon).prefix(3) == [PromptIcon.pen.rawValue, PromptIcon.check.rawValue, PromptIcon.sparkle.rawValue])
        #expect(migrated.prompts.count == 3 + Prompt.defaultPrompts.count)
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

struct ResponseCleanerMarkerTests {

    /// The input is wrapped in <<< / >>> markers (PromptBuilder); when a model
    /// echoes them around its answer, Notion pastes <<< literally and turns a
    /// >>> line into a quote block — the markers must be stripped.
    @Test func stripsInlineEchoedMarkers() {
        #expect(ResponseCleaner.clean("<<<Corrected text>>>", input: "original") == "Corrected text")
        #expect(ResponseCleaner.clean("  <<<\nCorrected text\n>>>  ", input: "original") == "Corrected text")
    }

    @Test func stripsLineFormEchoedMarkers() {
        #expect(ResponseCleaner.clean("<<<\nCorrected text\n>>>", input: "original") == "Corrected text")
        let multi = ResponseCleaner.clean("<<<\nLine one\nLine two\n>>>", input: "original")
        #expect(multi == "Line one\nLine two")
    }

    @Test func stripsMarkersEvenWhenAnswerContainsAngleBrackets() {
        let cleaned = ResponseCleaner.clean("<<<\n5 < 10 and 10 > 5\n>>>", input: "original")
        #expect(cleaned == "5 < 10 and 10 > 5")
    }

    /// Legitimate < and > characters must never be removed indiscriminately.
    @Test func preservesLegitimateAngleBrackets() {
        #expect(ResponseCleaner.clean("a < b and c > d", input: "a<b c>d") == "a < b and c > d")
        #expect(ResponseCleaner.clean("<div>hello</div>", input: "hello") == "<div>hello</div>")
        #expect(ResponseCleaner.clean(">>>", input: "x") == ">>>")
        #expect(ResponseCleaner.clean("<<<", input: "x") == "<<<")
        #expect(ResponseCleaner.clean("<<quoted>>", input: "quoted") == "<<quoted>>")
    }

    @Test func loneMarkerLinesArePreserved() {
        // A legitimate quote-style line in the answer is NOT a marker echo.
        #expect(ResponseCleaner.clean("> quoted line", input: "quoted") == "> quoted line")
    }

    @Test func markerOnlyAnswerBecomesEmptyAndIsRejectedUpstream() {
        #expect(ResponseCleaner.clean("<<<\n>>>", input: "original") == "")
    }
}
