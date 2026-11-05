import Foundation

/// Builds the chat messages sent to an LLM backend from a user prompt.
public enum PromptBuilder {

    /// Messages for a free-form user prompt (the prompt text is the instruction).
    public static func messages(prompt: String, text: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: systemPrompt(instruction: prompt)),
            ChatMessage(role: .user, content: userPrompt(text: text)),
        ]
    }

    private static func systemPrompt(instruction: String) -> String {
        """
        You are SpellCheck, a text editing assistant. The user gives you a piece of text. \
        \(instruction) \
        Output ONLY the resulting text. Do not add explanations, quotes, or commentary. \
        Preserve the original line breaks unless the instruction says otherwise.
        """
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

/// Minimal OpenAI-compatible chat completion request/response payloads.
public enum ChatCompletion {
    public struct Request: Codable, Sendable {
        public var model: String
        public var messages: [ChatMessage]
        public var temperature: Double

        public init(model: String, messages: [ChatMessage], temperature: Double = 0.2) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
        }
    }

    public struct Response: Codable, Sendable {
        public struct Choice: Codable, Sendable {
            public struct Message: Codable, Sendable {
                public var content: String?
            }
            public var message: Message
        }
        public var choices: [Choice]
    }
}
