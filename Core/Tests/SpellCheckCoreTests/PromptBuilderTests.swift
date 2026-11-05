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
        #expect(messages[0].content.contains("Output ONLY the resulting text"))
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
        #expect(response.choices.first?.message.content == "corrected text")
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

    @Test func fixGrammarPromptCarriesLegalTermsParagraph() {
        let fix = Prompt.defaultPrompts.first { $0.name == "Fix Grammar" }
        #expect(fix?.prompt.contains("skatteloven") == true)
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
