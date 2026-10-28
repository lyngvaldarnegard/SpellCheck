import Foundation

/// The built-in actions offered in the SpellCheck menu, mirroring what the
/// original FixKey-style apps expose.
public enum BuiltinAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case fixTypos = "Fix typos and grammar"
    case makeProfessional = "Make professional"
    case makeCasual = "Make casual"
    case summarize = "Summarize"
    case expand = "Expand"
    case translate = "Translate"

    public var id: String { rawValue }

    /// System prompt fragment describing the action.
    public var instruction: String {
        switch self {
        case .fixTypos:
            return "Fix all spelling mistakes, typos and grammar errors. Keep the meaning, language and tone unchanged."
        case .makeProfessional:
            return "Rewrite the text so it sounds professional and polished. Keep the meaning unchanged."
        case .makeCasual:
            return "Rewrite the text so it sounds casual and friendly. Keep the meaning unchanged."
        case .summarize:
            return "Summarize the text concisely. Keep the original language."
        case .expand:
            return "Expand the text with more detail and explanation. Keep the meaning and language unchanged."
        case .translate:
            return "Translate the text into the language the user names in the prompt."
        }
    }
}

/// Builds the chat messages sent to an LLM backend.
public enum PromptBuilder {

    /// Messages for a built-in action.
    public static func messages(action: BuiltinAction, text: String, language: String? = nil) -> [ChatMessage] {
        var instruction = action.instruction
        if action == .translate, let language, !language.isEmpty {
            instruction = "Translate the text into \(language)."
        }
        return [
            ChatMessage(role: .system, content: systemPrompt(instruction: instruction)),
            ChatMessage(role: .user, content: userPrompt(text: text)),
        ]
    }

    /// Messages for a free-form custom prompt.
    public static func messages(customPrompt prompt: String, text: String) -> [ChatMessage] {
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
