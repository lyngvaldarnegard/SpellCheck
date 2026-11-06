import Foundation
import Testing
@testable import SpellCheckCore

struct PromptBuilderTests {

    @Test func promptProducesSystemAndUserMessages() {
        let messages = PromptBuilder.messages(prompt: "Fix all spelling mistakes", text: "teh cat")
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[0].content.contains("Fix all spelling mistakes"))
        #expect(messages[1].role == .user)
        #expect(messages[1].content.contains("teh cat"))
    }

    @Test func systemPromptDemandsTextOnlyOutput() {
        let messages = PromptBuilder.messages(prompt: "Summarize this", text: "long text")
        #expect(messages[0].content.contains("Return ONLY the requested result"))
    }

    @Test func userPromptWrapsTextInMarkers() {
        let messages = PromptBuilder.messages(prompt: "Expand this", text: "abc")
        #expect(messages[1].content.contains("<<<"))
        #expect(messages[1].content.contains(">>>"))
    }

    @Test func chatCompletionRequestEncodes() throws {
        let request = ChatCompletion.Request(
            model: "gpt-4o-mini",
            messages: PromptBuilder.messages(prompt: "Fix grammar", text: "hi")
        )
        let data = try JSONEncoder().encode(request)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"model\":\"gpt-4o-mini\""))
        #expect(json.contains("\"role\":\"system\""))
        #expect(json.contains("\"temperature\":0.2"))
    }

    @Test func chatCompletionResponseDecodes() throws {
        let json = """
        {"choices":[{"message":{"content":"corrected text"}}]}
        """
        let response = try JSONDecoder().decode(ChatCompletion.Response.self, from: Data(json.utf8))
        #expect(response.choices.first?.message.content == .text("corrected text"))
        #expect(response.contentText == "corrected text")
    }

    // MARK: Shared prompt (issue #9)

    @Test func sharedPromptComesBeforeSelectedPrompt() {
        let messages = PromptBuilder.messages(
            prompt: "Improve the writing",
            sharedPrompt: "KEEP THE ORIGINAL LANGUAGE.",
            text: "en setning"
        )
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        let system = messages[0].content
        if let range = system.range(of: "KEEP THE ORIGINAL LANGUAGE."),
           let promptRange = system.range(of: "Improve the writing") {
            #expect(range.lowerBound < promptRange.lowerBound)
        } else {
            Issue.record("system message must contain shared prompt and selected prompt")
        }
        #expect(messages[1].role == .user)
        #expect(messages[1].content.contains("en setning"))
    }

    @Test func emptySharedPromptIsOmitted() {
        let messages = PromptBuilder.messages(prompt: "Fix grammar", sharedPrompt: "  \n ", text: "x")
        #expect(messages[0].content.contains("Fix grammar"))
        #expect(!messages[0].content.contains("\n\n\n"))
    }

    @Test func systemPromptAsksForLanguagePreservationAndNoDelimiters() {
        let messages = PromptBuilder.messages(prompt: "Summarize", sharedPrompt: "", text: "x")
        let system = messages[0].content
        #expect(system.contains("Preserve the original language"))
        #expect(system.contains("<<<"))
        #expect(system.contains("quotes, Markdown, or code fences"))
        #expect(system.contains("translation"))
    }

    // MARK: Lenient response parsing (issue #11)

    @Test func responseContentDecodesPartArrays() throws {
        let json = """
        {"choices":[{"message":{"content":[{"type":"text","text":"part one "},{"type":"text","text":"part two"}]}}]}
        """
        let response = try JSONDecoder().decode(ChatCompletion.Response.self, from: Data(json.utf8))
        #expect(response.contentText == "part one part two")
    }

    @Test func nullContentYieldsNoResultText() throws {
        let json = """
        {"choices":[{"message":{"content":null}}]}
        """
        let response = try JSONDecoder().decode(ChatCompletion.Response.self, from: Data(json.utf8))
        // No usable text — the backend reports an empty result (which is a
        // fallback-worthy condition), not a decoding crash.
        #expect(response.contentText == nil || response.contentText == "")
    }

    @Test func fallbackPolicyClassifiesErrors() {
        #expect(CorrectionError.http(status: 429, message: "capacity").isRetryableWithBackup)
        #expect(CorrectionError.http(status: 503, message: "unavailable").isRetryableWithBackup)
        #expect(CorrectionError.emptyResponse.isRetryableWithBackup)
        #expect(CorrectionError.unusableResponse("bad format").isRetryableWithBackup)
        #expect(!CorrectionError.http(status: 401, message: "bad key").isRetryableWithBackup)
        #expect(!CorrectionError.http(status: 400, message: "bad request").isRetryableWithBackup)
        #expect(!CorrectionError.notConfigured.isRetryableWithBackup)
        #expect(FallbackPolicy.shouldFallback(after: URLError(.timedOut)))
        #expect(!FallbackPolicy.shouldFallback(after: CorrectionError.cancelled))
    }
}

struct PromptTests {

    @Test func defaultPromptsAreEditableEntries() {
        let prompts = Prompt.defaultPrompts
        #expect(prompts.count >= 7)
        #expect(prompts.contains { $0.name == "Fix Grammar" })
        #expect(prompts.contains { $0.name == "Translate to English" })
        for prompt in prompts {
            #expect(!prompt.name.isEmpty)
            #expect(!prompt.prompt.isEmpty)
            #expect(PromptIcon(rawValue: prompt.icon) != nil)
        }
    }

    @Test func defaultPromptsContainNoNorwegianText() {
        // All GitHub/repository content must be English-only (user rule),
        // including the seeded prompt texts. The two Norwegian-language
        // translation prompts are exempt: their names and bodies necessarily
        // contain the target language's own name (Bokmål/Nynorsk).
        for prompt in Prompt.defaultPrompts {
            if prompt.name.hasPrefix("Translate to Norwegian") { continue }
            for scalar in prompt.prompt.unicodeScalars {
                #expect(["æ", "ø", "å", "Æ", "Ø", "Å"].contains(String(scalar)) == false)
            }
        }
    }

    @Test func defaultPromptsDropAllvitNapoloenAndJuss() {
        #expect(Prompt.defaultPrompts.contains { $0.name == "Allvit" } == false)
        #expect(Prompt.defaultPrompts.contains { $0.name == "Napoloen" } == false)
        #expect(Prompt.defaultPrompts.contains { $0.name == "Juss" } == false)
        // The Napoloen prompt survives as "Humanize" (Norwegian sections removed).
        #expect(Prompt.defaultPrompts.contains { $0.name == "Humanize" } == true)
    }

    @Test func translationPromptsAreAtTheBottomOfTheDefaults() {
        let names = Prompt.defaultPrompts.map(\.name)
        let translationNames = names.filter { $0.hasPrefix("Translate to") || $0 == "Pinyin to Chinese" }
        #expect(translationNames.count >= 10)
        // Every translation prompt comes after every non-translation prompt.
        if let firstTranslation = names.firstIndex(where: { $0.hasPrefix("Translate to") || $0 == "Pinyin to Chinese" }) {
            for name in names[..<firstTranslation] {
                #expect(name.hasPrefix("Translate to") == false && name != "Pinyin to Chinese")
            }
        }
    }

    @Test func promptIsCodable() throws {
        let prompt = Prompt(name: "Pirate", prompt: "Rewrite as a pirate", icon: PromptIcon.sparkle.rawValue)
        let data = try JSONEncoder().encode(prompt)
        let decoded = try JSONDecoder().decode(Prompt.self, from: data)
        #expect(decoded == prompt)
    }

    @Test func unknownIconFallsBackToCheck() {
        let prompt = Prompt(name: "X", prompt: "Y", icon: "not-an-icon")
        #expect(prompt.iconKind == .check)
    }
}

struct APIProviderTests {

    @Test func presetsPairBaseURLWithAConsistentModel() {
        for provider in APIProvider.allCases {
            #expect(provider.baseURL.hasPrefix("http"))
            switch provider {
            case .mistral:
                #expect(provider.baseURL == "https://api.mistral.ai/v1")
                #expect(provider.defaultModel.hasPrefix("mistral"))
            case .openAI:
                #expect(provider.baseURL == "https://api.openai.com/v1")
                #expect(!provider.defaultModel.contains("deepseek"))
                #expect(!provider.defaultModel.contains("mistral"))
            case .deepSeek:
                #expect(provider.baseURL == "https://api.deepseek.com/v1")
                #expect(provider.defaultModel.hasPrefix("deepseek"))
            case .openRouter:
                #expect(provider.baseURL == "https://openrouter.ai/api/v1")
                #expect(provider.defaultModel.contains("/"))
            case .ollama:
                #expect(provider.baseURL == "http://localhost:11434/v1")
            }
        }
    }

    @Test func matchingProviderIsDetectedFromBaseURL() {
        #expect(APIProvider.matching(baseURL: "https://api.mistral.ai/v1") == .mistral)
        #expect(APIProvider.matching(baseURL: "  https://api.mistral.ai/v1  ") == .mistral)
        #expect(APIProvider.matching(baseURL: "https://example.com/v1") == nil)
    }
}
