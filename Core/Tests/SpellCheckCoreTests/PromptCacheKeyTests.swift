import Foundation
import Testing
@testable import SpellCheckCore

struct PromptCacheKeyTests {

    @Test func samePromptsProduceSameKey() {
        let a = PromptCacheKey.make(sharedPrompt: "Always answer briefly.", prompt: "Fix grammar only")
        let b = PromptCacheKey.make(sharedPrompt: "Always answer briefly.", prompt: "Fix grammar only")
        #expect(a == b)
    }

    @Test func differentPromptsProduceDifferentKeys() {
        let a = PromptCacheKey.make(sharedPrompt: "Always answer briefly.", prompt: "Fix grammar only")
        let b = PromptCacheKey.make(sharedPrompt: "Always answer briefly.", prompt: "Make shorter")
        let c = PromptCacheKey.make(sharedPrompt: "Different shared prompt.", prompt: "Fix grammar only")
        #expect(a != b)
        #expect(a != c)
    }

    @Test func whitespaceOnlyChangesKeepTheKeyStable() {
        let a = PromptCacheKey.make(sharedPrompt: "Always answer briefly.", prompt: "Fix grammar only")
        let b = PromptCacheKey.make(sharedPrompt: "  Always answer briefly.\n ", prompt: "Fix grammar only\n\n")
        #expect(a == b)
    }

    @Test func keyNeverContainsPromptContentsOrText() {
        let shared = "SECRETSHAREDINSTRUCTION"
        let prompt = "SECRETPROMPTINSTRUCTION"
        let key = PromptCacheKey.make(sharedPrompt: shared, prompt: prompt)
        #expect(!key.contains(shared))
        #expect(!key.contains(prompt))
        #expect(key.hasPrefix("spellcheck-"))
        // hex digest only after the prefix
        let digest = String(key.dropFirst("spellcheck-".count))
        #expect(digest.allSatisfy { $0.isHexDigit })
        #expect(digest.count == 16)
    }

    @Test func requestOmitsCacheKeyWhenNil() throws {
        let request = ChatCompletion.Request(
            model: "mistral-small-latest",
            messages: [ChatMessage(role: .system, content: "sys"), ChatMessage(role: .user, content: "hi")]
        )
        let data = try JSONEncoder().encode(request)
        let body = String(decoding: data, as: UTF8.self)
        #expect(!body.contains("prompt_cache_key"))
    }

    @Test func requestIncludesCacheKeyWhenSet() throws {
        let request = ChatCompletion.Request(
            model: "mistral-small-latest",
            messages: [ChatMessage(role: .system, content: "sys")],
            promptCacheKey: "spellcheck-0123456789abcdef"
        )
        let data = try JSONEncoder().encode(request)
        let body = String(decoding: data, as: UTF8.self)
        #expect(body.contains("\"prompt_cache_key\":\"spellcheck-0123456789abcdef\""))
        // prompt ordering and content are unchanged by the cache key
        #expect(body.contains("\"model\":\"mistral-small-latest\""))
        #expect(body.contains("\"role\":\"system\""))
    }

    @Test func decodesMistralCachedTokenUsage() throws {
        let sample = """
        {
          "id": "a4db7c530548494f8ff9986bcd2a7737",
          "created": 1773840064,
          "model": "mistral-large-latest",
          "usage": {
            "prompt_tokens": 1013,
            "total_tokens": 1043,
            "completion_tokens": 30,
            "prompt_tokens_details": { "cached_tokens": 1008 }
          },
          "object": "chat.completion",
          "choices": [
            { "message": { "content": "ok" } }
          ]
        }
        """
        let response = try JSONDecoder().decode(ChatCompletion.Response.self, from: Data(sample.utf8))
        #expect(response.contentText == "ok")
        #expect(response.cachedPromptTokens == 1008)
        #expect(response.usage?.prompt_tokens == 1013)
    }

    @Test func usageIsOptional() throws {
        let sample = """
        { "choices": [ { "message": { "content": "hello" } } ] }
        """
        let response = try JSONDecoder().decode(ChatCompletion.Response.self, from: Data(sample.utf8))
        #expect(response.contentText == "hello")
        #expect(response.cachedPromptTokens == nil)
    }
}
