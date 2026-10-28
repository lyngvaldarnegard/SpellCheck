import Foundation
import Testing
@testable import SpellCheckCore

struct PromptBuilderTests {

    @Test func builtinActionProducesSystemAndUserMessages() {
        let messages = PromptBuilder.messages(action: .fixTypos, text: "teh cat")
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[0].content.contains("Fix all spelling mistakes"))
        #expect(messages[1].role == .user)
        #expect(messages[1].content.contains("teh cat"))
    }

    @Test func systemPromptDemandsTextOnlyOutput() {
        let messages = PromptBuilder.messages(action: .summarize, text: "long text")
        #expect(messages[0].content.contains("Output ONLY the resulting text"))
    }

    @Test func translateUsesConfiguredLanguage() {
        let messages = PromptBuilder.messages(action: .translate, text: "hello", language: "French")
        #expect(messages[0].content.contains("Translate the text into French."))
    }

    @Test func translateWithoutLanguageFallsBackToPrompt() {
        let messages = PromptBuilder.messages(action: .translate, text: "hello", language: nil)
        #expect(messages[0].content.contains("the language the user names in the prompt"))
    }

    @Test func customPromptIsUsedAsInstruction() {
        let messages = PromptBuilder.messages(customPrompt: "Make this sound like a pirate", text: "hi there")
        #expect(messages[0].content.contains("Make this sound like a pirate"))
        #expect(messages[1].content.contains("hi there"))
    }

    @Test func userPromptWrapsTextInMarkers() {
        let messages = PromptBuilder.messages(action: .expand, text: "abc")
        #expect(messages[1].content.contains("<<<"))
        #expect(messages[1].content.contains(">>>"))
    }

    @Test func chatCompletionRequestEncodes() throws {
        let request = ChatCompletion.Request(
            model: "gpt-4o-mini",
            messages: PromptBuilder.messages(action: .fixTypos, text: "hi")
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
