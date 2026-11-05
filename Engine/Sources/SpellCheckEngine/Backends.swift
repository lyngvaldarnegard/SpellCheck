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

    public init(apiKey: String, model: String, baseURL: String) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    public func correct(text: String, prompt: String) async throws -> String {
        guard isReady else { throw CorrectionError.notConfigured }
        guard let url = APIEndpoint.chatCompletionsURL(baseURL) else {
            throw CorrectionError.backendFailed("The API base URL is not valid")
        }
        let messages = PromptBuilder.messages(prompt: prompt, text: text)
        let payload = ChatCompletion.Request(model: model.isEmpty ? APIProvider.openAI.defaultModel : model, messages: messages)

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
            let body = String(data: data, encoding: .utf8).map { " \($0)" } ?? ""
            throw CorrectionError.backendFailed("API request failed with status \(http.statusCode)\(body)")
        }
        let decoded = try JSONDecoder().decode(ChatCompletion.Response.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw CorrectionError.emptyResponse
        }
        return content
    }
}
