import Foundation
import Testing
import SpellCheckCore
@testable import SpellCheckEngine

struct RuleBasedBackendTests {

    @Test func correctsTypos() async throws {
        let backend = RuleBasedBackend()
        let output = try await backend.correct(text: "I will recieve it", action: .fixTypos)
        #expect(output == "I will receive it")
    }

    @Test func rejectsNonTypoActions() async {
        let backend = RuleBasedBackend()
        await #expect(throws: CorrectionError.self) {
            _ = try await backend.correct(text: "hello", action: .summarize, customPrompt: nil, language: nil)
        }
    }

    @Test func rejectsCustomPrompts() async {
        let backend = RuleBasedBackend()
        await #expect(throws: CorrectionError.self) {
            _ = try await backend.correct(text: "hello", action: .fixTypos, customPrompt: "pirate", language: nil)
        }
    }

    @Test func returnsInputWhenNothingToFix() async throws {
        let backend = RuleBasedBackend()
        let output = try await backend.correct(text: "All good here.", action: .fixTypos)
        #expect(output == "All good here.")
    }
}

struct OpenAICompatibleBackendTests {

    @Test func notReadyWithoutKey() {
        let backend = OpenAICompatibleBackend(apiKey: "", model: "m", baseURL: "https://api.openai.com/v1")
        #expect(backend.isReady == false)
    }

    @Test func throwsWhenNotConfigured() async {
        let backend = OpenAICompatibleBackend(apiKey: "", model: "m", baseURL: "https://api.openai.com/v1")
        await #expect(throws: CorrectionError.notConfigured) {
            _ = try await backend.correct(text: "hi", action: .fixTypos, customPrompt: nil, language: nil)
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
            next.backend = .openAICompatible
            next.customPrompts = [CustomPrompt(name: "Pirate", prompt: "Rewrite as a pirate")]
            return next
        }

        let reloaded = try SettingsStore(directory: dir)
        let settings = await reloaded.load()
        #expect(settings.apiKey == "sk-test")
        #expect(settings.backend == .openAICompatible)
        #expect(settings.customPrompts.count == 1)
        #expect(settings.customPrompts.first?.name == "Pirate")
    }

    @Test func missingFileYieldsDefaults() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directory: dir)
        #expect(await store.load() == .default)
    }
}
