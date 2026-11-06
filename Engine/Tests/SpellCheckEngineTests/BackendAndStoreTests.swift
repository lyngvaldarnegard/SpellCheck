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

    /// The user's chosen prompt order must survive a restart (a brand-new
    /// store on the same settings file).
    @Test func promptOrderSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var settings = Settings.default
        settings.didSeedDefaultPrompts = true
        settings.prompts = [
            Prompt(name: "First", prompt: "1"),
            Prompt(name: "Second", prompt: "2"),
            Prompt(name: "Third", prompt: "3"),
        ]
        let initial = settings
        let store = try SettingsStore(directory: dir)
        try await store.update { _ in initial }

        // Simulate the user reordering in the editor and saving.
        try await store.update { current in
            var next = current
            let second = next.prompts.remove(at: 1)
            next.prompts.insert(second, at: 0)
            return next
        }

        let reopened = try SettingsStore(directory: dir)
        let final = await reopened.load()
        #expect(final.prompts.map(\.name) == ["Second", "First", "Third"])
        #expect(final.prompts.map(\.prompt) == ["2", "1", "3"])
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

// MARK: - Fallback model (issues #10/#11)

private final class ScriptedBackend: CorrectionBackend, @unchecked Sendable {
    let displayName: String
    var isReady = true
    var error: (any Error)?
    var response = "result"
    private(set) var calls: [(text: String, prompt: String, shared: String)] = []

    init(displayName: String, error: (any Error)? = nil) {
        self.displayName = displayName
        self.error = error
    }

    func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
        calls.append((text, prompt, sharedPrompt))
        if let error { throw error }
        return response
    }
}

struct FallbackBackendTests {

    @Test func retryablePrimaryFailureFallsBackWithSameRequest() async throws {
        let primary = ScriptedBackend(
            displayName: "primary",
            error: CorrectionError.http(status: 429, message: "Not enough capacity available for this request. (backend_out_of_capacity)")
        )
        let backup = ScriptedBackend(displayName: "backup")
        backup.response = "backup result"
        let backend = FallbackBackend(primary: primary, backupModel: "mistral-small-latest") { _ in backup }

        let result = try await backend.correct(text: "some text", prompt: "Fix grammar", sharedPrompt: "keep language")
        #expect(result == "backup result")
        #expect(primary.calls.count == 1)
        #expect(backup.calls.count == 1)
        // The backup gets the exact same shared prompt, prompt and text.
        #expect(backup.calls[0].text == "some text")
        #expect(backup.calls[0].prompt == "Fix grammar")
        #expect(backup.calls[0].shared == "keep language")
    }

    @Test func unusableResponseFallsBack() async throws {
        let primary = ScriptedBackend(displayName: "primary", error: CorrectionError.unusableResponse("bad format"))
        let backup = ScriptedBackend(displayName: "backup")
        let backend = FallbackBackend(primary: primary, backupModel: "m") { _ in backup }
        let result = try await backend.correct(text: "t", prompt: "p", sharedPrompt: "s")
        #expect(result == "result")
        #expect(backup.calls.count == 1)
    }

    @Test func authenticationFailureDoesNotFallBack() async {
        let primary = ScriptedBackend(displayName: "primary", error: CorrectionError.http(status: 401, message: "bad key"))
        let backup = ScriptedBackend(displayName: "backup")
        let backend = FallbackBackend(primary: primary, backupModel: "m") { _ in backup }

        await #expect(throws: CorrectionError.self) {
            _ = try await backend.correct(text: "t", prompt: "p", sharedPrompt: "s")
        }
        #expect(backup.calls.isEmpty)
    }

    @Test func bothFailuresDescribeBothAttempts() async {
        let primary = ScriptedBackend(displayName: "primary", error: CorrectionError.http(status: 503, message: "down"))
        let backup = ScriptedBackend(displayName: "backup", error: CorrectionError.http(status: 429, message: "rate limited"))
        let backend = FallbackBackend(primary: primary, backupModel: "mistral-small-latest") { _ in backup }

        do {
            _ = try await backend.correct(text: "t", prompt: "p", sharedPrompt: "s")
            Issue.record("expected a combined error")
        } catch let error as CorrectionError {
            guard case .backendFailed(let message) = error else {
                Issue.record("expected backendFailed, got \(error)")
                return
            }
            #expect(message.contains("mistral-small-latest"))
            #expect(message.contains("down"))
            #expect(message.contains("rate limited"))
        } catch {
            Issue.record("unexpected error type")
        }
    }

    @Test func emptyBackupModelDisablesFallback() async throws {
        let primary = ScriptedBackend(displayName: "primary", error: CorrectionError.http(status: 500, message: "boom"))
        // makeBackup must never even be asked for a backend
        let backend = FallbackBackend(primary: primary, backupModel: "   ") { _ in
            Issue.record("backup backend created for an empty backup model")
            return ScriptedBackend(displayName: "backup")
        }
        await #expect(throws: CorrectionError.self) {
            _ = try await backend.correct(text: "t", prompt: "p", sharedPrompt: "s")
        }
    }

    @Test func timeoutFallsBack() async throws {
        let primary = ScriptedBackend(displayName: "primary", error: URLError(.timedOut))
        let backup = ScriptedBackend(displayName: "backup")
        let backend = FallbackBackend(primary: primary, backupModel: "m") { _ in backup }
        let result = try await backend.correct(text: "t", prompt: "p", sharedPrompt: "s")
        #expect(result == "result")
    }
}

struct BackendErrorParsingTests {

    @Test func errorMessageExtractsProviderMessageAndCode() {
        let body = Data("""
        {"error":{"message":"Not enough capacity available for this request.","code":"backend_out_of_capacity"}}
        """.utf8)
        let message = OpenAICompatibleBackend.errorMessage(from: body)
        #expect(message.contains("Not enough capacity available"))
        #expect(message.contains("backend_out_of_capacity"))
    }

    @Test func errorMessageHandlesUnparseableBody() {
        #expect(OpenAICompatibleBackend.errorMessage(from: Data("gateway timeout".utf8)) == "The API request failed")
    }

    @Test func httpErrorCarriesStatusForFallbackDecisions() {
        let error = CorrectionError.http(status: 429, message: "capacity")
        #expect(error.isRetryableWithBackup)
    }
}
