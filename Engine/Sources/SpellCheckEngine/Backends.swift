import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SpellCheckCore

/// Backend talking to any OpenAI-compatible chat completions endpoint
/// (Mistral, OpenAI, DeepSeek, OpenRouter, Ollama, LM Studio, …).
public struct OpenAICompatibleBackend: CorrectionBackend {
    public let apiKey: String
    public let model: String
    public let baseURL: String

    public static let requestTimeout: TimeInterval = 120

    public var displayName: String { "OpenAI-compatible API" }
    public var isReady: Bool { !apiKey.isEmpty }
    public var modelKey: String { model }

    public init(apiKey: String, model: String, baseURL: String) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    public func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
        guard isReady else { throw CorrectionError.notConfigured }
        guard let url = APIEndpoint.chatCompletionsURL(baseURL) else {
            throw CorrectionError.backendFailed("The API base URL is not valid")
        }
        let messages = PromptBuilder.messages(prompt: prompt, sharedPrompt: sharedPrompt, text: text)
        let payload = Self.requestPayload(
            model: model.isEmpty ? APIProvider.openAI.defaultModel : model,
            messages: messages,
            promptCacheKey: Self.promptCacheKey(baseURL: baseURL, sharedPrompt: sharedPrompt, prompt: prompt)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.requestTimeout
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CorrectionError.backendFailed("Invalid response from the API server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CorrectionError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        do {
            let decoded = try JSONDecoder().decode(ChatCompletion.Response.self, from: data)
            guard let content = decoded.contentText, !content.isEmpty else {
                throw CorrectionError.emptyResponse
            }
            return content
        } catch let error as CorrectionError {
            throw error
        } catch {
            // The provider answered 2xx but with a payload SpellCheck cannot
            // read (e.g. a model or endpoint that is not fully OpenAI-compatible).
            // Surface an actionable error instead of a raw decoding failure.
            throw CorrectionError.unusableResponse(
                "The response from the model “\(model)” could not be read — it is not in the expected format. " +
                "Check the model name and base URL in Settings, or try a different model."
            )
        }
    }

    /// Builds the chat completion request payload, including the provider's
    /// prompt cache key when one applies.
    static func requestPayload(
        model: String,
        messages: [ChatMessage],
        promptCacheKey: String?
    ) -> ChatCompletion.Request {
        ChatCompletion.Request(model: model, messages: messages, promptCacheKey: promptCacheKey)
    }

    /// The prompt cache key to send, or nil when the provider does not
    /// document support for one. Mistral's `prompt_cache_key` routes requests
    /// with identical prefixes together to raise (not guarantee) cache-hit
    /// rates; other OpenAI-compatible providers get an unchanged body so no
    /// unsupported parameter is ever sent. The key is derived only from the
    /// repeating instruction prefix (shared prompt + selected prompt) — never
    /// from API keys, user text, or anything sensitive.
    static func promptCacheKey(baseURL: String, sharedPrompt: String, prompt: String) -> String? {
        guard let host = URL(string: baseURL)?.host?.lowercased(), host.hasSuffix("mistral.ai") else {
            return nil
        }
        return PromptCacheKey.make(sharedPrompt: sharedPrompt, prompt: prompt)
    }

    /// Short, sanitized error summary from a provider error body. Never
    /// includes the full payload (it could contain echoed user text).
    static func errorMessage(from data: Data) -> String {
        struct ErrorPayload: Decodable {
            struct ErrorBody: Decodable {
                let message: String?
                let code: String?
            }
            let error: ErrorBody?
            let message: String?
            let detail: String?
        }
        guard let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) else {
            return "The API request failed"
        }
        let body = payload.error
        var parts: [String] = []
        if let message = body?.message ?? payload.message ?? payload.detail, !message.isEmpty {
            parts.append(String(message.prefix(200)))
        }
        if let code = body?.code, !code.isEmpty {
            parts.append("(\(code))")
        }
        return parts.isEmpty ? "The API request failed" : parts.joined(separator: " ")
    }
}

/// Retries the same request (shared prompt, selected prompt and text) once on
/// a backup model when the primary model fails for a temporary or
/// compatibility-related reason (capacity, rate limit, server failure, timeout,
/// empty or unreadable response). Never loops: at most one attempt per model,
/// each bounded by the backend's own request timeout. If both fail, the error
/// describes both attempts so the underlying problem stays visible.
public struct FallbackBackend: CorrectionBackend {
    private let primary: any CorrectionBackend
    private let backup: (model: String, backend: any CorrectionBackend)?

    public init(primary: any CorrectionBackend, backupModel: String, makeBackup: (String) -> any CorrectionBackend) {
        self.primary = primary
        let trimmed = backupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.backup = trimmed.isEmpty ? nil : (trimmed, makeBackup(trimmed))
    }

    public var displayName: String { primary.displayName }
    public var isReady: Bool { primary.isReady }
    /// Timing samples are attributed to the primary model; a fallback retry
    /// takes longer, but the estimate only needs to be a rough guide.
    public var modelKey: String { primary.modelKey }

    public func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
        do {
            return try await primary.correct(text: text, prompt: prompt, sharedPrompt: sharedPrompt)
        } catch {
            guard let backup, backup.backend.isReady, FallbackPolicy.shouldFallback(after: error) else {
                throw error
            }
            do {
                return try await backup.backend.correct(text: text, prompt: prompt, sharedPrompt: sharedPrompt)
            } catch let backupError {
                throw CorrectionError.backendFailed(
                    "The primary model failed: \(CorrectionEngine.message(for: error))\n" +
                    "The backup model “\(backup.model)” also failed: \(CorrectionEngine.message(for: backupError))"
                )
            }
        }
    }
}
