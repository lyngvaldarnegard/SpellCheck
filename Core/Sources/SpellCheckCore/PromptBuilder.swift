import Foundation

/// Builds the chat messages sent to an LLM backend from a user prompt.
public enum PromptBuilder {

    /// Messages for a free-form user prompt (the prompt text is the instruction).
    public static func messages(prompt: String, text: String) -> [ChatMessage] {
        messages(prompt: prompt, sharedPrompt: "", text: text)
    }

    /// Messages for one edit: the shared prompt (a common instruction included
    /// in every request), then the selected prompt's instruction, then the
    /// selected text. Kept in a system message (instructions) plus a user
    /// message (the text), preserving that logical order.
    public static func messages(prompt: String, sharedPrompt: String, text: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: systemPrompt(instruction: prompt, sharedPrompt: sharedPrompt)),
            ChatMessage(role: .user, content: userPrompt(text: text)),
        ]
    }

    private static func systemPrompt(instruction: String, sharedPrompt: String) -> String {
        var parts = [
            "You are SpellCheck, a text editing assistant. The user gives you a piece of text and an instruction."
        ]
        let shared = sharedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shared.isEmpty {
            parts.append(shared)
        }
        parts.append(instruction)
        parts.append(
            """
            Return ONLY the requested result — no explanations, preambles, apologies, \
            or commentary. Never include the input markers <<< or >>> in your output. \
            Do not wrap plain-text output in quotes, Markdown, or code fences; only use \
            such formatting when the instruction or the text explicitly requires it. \
            Preserve the original language of the text unless the instruction explicitly \
            asks for a translation or another language. Preserve the original meaning, \
            names, numbers, dates, links, and line breaks unless the instruction says otherwise.
            """
        )
        return parts.joined(separator: "\n\n")
    }

    private static func userPrompt(text: String) -> String {
        """
        Text:
        <<<
        \(text)
        >>>
        """
    }
}

/// A single chat message in an OpenAI-compatible chat completion request.
public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// A chat completion response's message content. Some OpenAI-compatible
/// providers return the content as an array of typed parts instead of a
/// plain string, or as `null` (e.g. when the model refuses or errors); both
/// variations decode instead of failing the whole response.
public enum ResponseContent: Equatable, Sendable, Codable {
    case text(String)
    case parts([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let parts = try? container.decode([ContentPart].self) {
            self = .parts(parts.compactMap(\.text))
        } else if container.decodeNil() {
            self = .text("")
        } else {
            self = .text("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string): try container.encode(string)
        case .parts(let parts): try container.encode(parts)
        }
    }

    /// The concatenated text of the content, whatever shape it arrived in.
    public var stringValue: String {
        switch self {
        case .text(let string): return string
        case .parts(let parts): return parts.joined()
        }
    }

    private struct ContentPart: Codable, Sendable {
        let text: String?
    }
}

/// Minimal OpenAI-compatible chat completion request/response payloads.
public enum ChatCompletion {
    public struct Request: Codable, Sendable {
        public var model: String
        public var messages: [ChatMessage]
        public var temperature: Double
        /// Provider-specific prompt cache routing key (e.g. Mistral's
        /// `prompt_cache_key`). Nil for providers without documented support —
        /// the field is then omitted from the JSON body entirely.
        public var promptCacheKey: String?

        public init(model: String, messages: [ChatMessage], temperature: Double = 0.2, promptCacheKey: String? = nil) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.promptCacheKey = promptCacheKey
        }

        private enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case promptCacheKey = "prompt_cache_key"
        }
    }

    public struct Response: Codable, Sendable {
        public struct Choice: Codable, Sendable {
            public struct Message: Codable, Sendable {
                public var content: ResponseContent?
            }
            public var message: Message
        }
        public struct Usage: Codable, Sendable {
            public struct PromptTokensDetails: Codable, Sendable {
                /// Tokens served from the provider's prompt cache (Mistral).
                public var cached_tokens: Int?
            }
            public var prompt_tokens: Int?
            public var completion_tokens: Int?
            public var total_tokens: Int?
            public var prompt_tokens_details: PromptTokensDetails?
        }
        public var choices: [Choice]
        public var usage: Usage?

        /// The response's text, tolerating the variations providers emit
        /// (string content, part arrays, or missing/null content).
        public var contentText: String? {
            choices.first?.message.content?.stringValue
        }

        /// How many prompt tokens were served from the provider's cache, when
        /// the provider reports it. Nil when the provider does not report
        /// cache usage.
        public var cachedPromptTokens: Int? {
            usage?.prompt_tokens_details?.cached_tokens
        }
    }
}
