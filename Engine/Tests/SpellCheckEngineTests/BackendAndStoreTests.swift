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
}
