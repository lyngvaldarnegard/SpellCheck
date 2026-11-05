import Foundation
import Testing
import SpellCheckCore
@testable import SpellCheckEngine

struct OpenAICompatibleBackendTests {

    @Test func notReadyWithoutKey() {
        let backend = OpenAICompatibleBackend(apiKey: "", model: "m", baseURL: "https://api.openai.com/v1")
        #expect(backend.isReady == false)
    }

    @Test func throwsWhenNotConfigured() async {
        let backend = OpenAICompatibleBackend(apiKey: "", model: "m", baseURL: "https://api.openai.com/v1")
        await #expect(throws: CorrectionError.notConfigured) {
            _ = try await backend.correct(text: "hi", prompt: "Fix grammar")
        }
    }

    @Test func invalidBaseURLIsReported() async {
        let backend = OpenAICompatibleBackend(apiKey: "sk", model: "m", baseURL: "not a url")
        await #expect(throws: CorrectionError.self) {
            _ = try await backend.correct(text: "hi", prompt: "Fix grammar")
        }
    }
}

struct SettingsStoreTests {

    @Test func roundTripsThroughDisk() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directory: dir)

        try await store.update { current in
            var next = current
            next.apiKey = "sk-test"
            next.prompts = [Prompt(name: "Pirate", prompt: "Rewrite as a pirate")]
            return next
        }

        let reloaded = try SettingsStore(directory: dir)
        let settings = await reloaded.load()
        #expect(settings.apiKey == "sk-test")
        #expect(settings.prompts.count == 1)
        #expect(settings.prompts.first?.name == "Pirate")
    }

    @Test func missingFileYieldsDefaults() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directory: dir)
        #expect(await store.load() == .default)
    }

    @Test func updateThrowsWhenDirectoryIsUnwritable() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directory: dir)
        await #expect(throws: Error.self) {
            try await store.update { _ in
                var next = Settings.default
                next.apiKey = "x"
                return next
            }
            // second update with a deleted directory must fail, not silently pass
            try FileManager.default.removeItem(at: dir)
            try await store.update { _ in Settings.default }
        }
    }

    // MARK: Prompt persistence across updates / restarts

    /// Simulates an app update: the settings file written by an older
    /// version (with the user's prompts, API key and other settings) is
    /// loaded by a "new" store and re-saved — everything must survive.
    @Test func promptsSurviveUpdateAndRestart() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var old = Settings.default
        old.apiKey = "sk-keep-me"
        old.model = "mistral-small-latest"
        old.baseURL = "https://api.mistral.ai/v1"
        old.launchAtLogin = true
        old.menuBarIconStyle = "omega"
        old.didSeedDefaultPrompts = true
        old.prompts = [
            Prompt(name: "Allvit", prompt: "Skriv retts- og lovnavn i fullt, for eksempel «skatteloven» i stedet for «sktl.». Behold FSFIN forkortet. Æøå test — \u{1F600}", icon: PromptIcon.pen.rawValue),
            Prompt(name: "Juss", prompt: "Polish legal text \u{2013} keep § references", icon: PromptIcon.question.rawValue),
            Prompt(name: "Empty body", prompt: "", icon: PromptIcon.check.rawValue),
        ]
        let oldData = try JSONEncoder().encode(old)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try oldData.write(to: dir.appendingPathComponent("settings.json"))

        // "New version" opens the same file, migrates and re-saves.
        let updated = try SettingsStore(directory: dir)
        let loaded = await updated.load()
        let migrated = loaded.migrated()
        try await updated.update { _ in migrated }

        // Simulate a full restart: a brand-new store on the same file.
        let reopened = try SettingsStore(directory: dir)
        let final = await reopened.load()
        #expect(final.apiKey == "sk-keep-me")
        #expect(final.model == "mistral-small-latest")
        #expect(final.baseURL == "https://api.mistral.ai/v1")
        #expect(final.launchAtLogin == true)
        #expect(final.menuBarIconStyle == "omega")
        #expect(final.prompts.count == 3)
        #expect(final.prompts.map(\.name) == ["Allvit", "Juss", "Empty body"])
        #expect(final.prompts[0].prompt.contains("«skatteloven»"))
        #expect(final.prompts[0].prompt.contains("Æøå"))
        #expect(final.prompts[1].icon == PromptIcon.question.rawValue)
    }

    /// An intentionally emptied prompt list must NOT be re-seeded with
    /// defaults when the app updates or restarts.
    @Test func deliberatelyEmptyPromptListSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var settings = Settings.default
        settings.apiKey = "sk-keep-me"
        settings.didSeedDefaultPrompts = true
        settings.prompts = []
        let migrated = settings.migrated()
        let store = try SettingsStore(directory: dir)
        try await store.update { _ in migrated }

        let reopened = try SettingsStore(directory: dir)
        let final = await reopened.load()
        #expect(final.prompts.isEmpty)
        #expect(final.apiKey == "sk-keep-me")
    }

    /// A settings file that cannot be decoded (e.g. truncated by a crash
    /// during an update) must be backed up, not silently overwritten.
    @Test func corruptSettingsFileIsBackedUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try Data("{\"apiKey\": \"sk-".utf8).write(to: file)

        let store = try SettingsStore(directory: dir)
        #expect(await store.load() == .default)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("settings.corrupt-") }
        #expect(backups.count == 1)
        let backupData = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("settings.corrupt-") }
            .map { try Data(contentsOf: $0) }
        #expect(backupData == Data("{\"apiKey\": \"sk-".utf8))
    }
}
