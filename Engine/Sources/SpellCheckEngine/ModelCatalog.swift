import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SpellCheckCore

/// Fetches and parses the model list exposed by an OpenAI-compatible provider
/// (`GET {base}/models`), so the user can pick a model instead of typing one.
public enum ModelCatalog {

    /// Shape of the `GET /models` response (OpenAI, DeepSeek, OpenRouter, …).
    public struct ListResponse: Codable, Sendable {
        public struct Model: Codable, Sendable {
            public var id: String
        }
        public var data: [Model]
    }

    /// Parses a `/models` response body into a de-duplicated list of IDs.
    /// Models with "latest" in the name come first (the provider's
    /// current-generation variant of each family — mistral, magistral,
    /// voxtral, ...), alphabetical within each group, then the rest
    /// alphabetically.
    public static func parseModelIDs(from data: Data) throws -> [String] {
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        let ids = decoded.data.map(\.id).filter { !$0.isEmpty }
        return Array(Set(ids)).sorted { lhs, rhs in
            let lhsLatest = lhs.localizedCaseInsensitiveContains("latest")
            let rhsLatest = rhs.localizedCaseInsensitiveContains("latest")
            if lhsLatest != rhsLatest { return lhsLatest }
            return lhs < rhs
        }
    }

    /// Calls the provider's model list endpoint. The API key is optional —
    /// local servers (Ollama, LM Studio) don't require one.
    public static func fetchModels(apiKey: String, baseURL: String) async throws -> [String] {
        guard let url = APIEndpoint.modelsURL(baseURL) else {
            throw CorrectionError.backendFailed("The API base URL is not valid")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CorrectionError.backendFailed("Invalid response from the API server")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8).map { " \($0)" } ?? ""
            throw CorrectionError.backendFailed("Could not fetch models (status \(http.statusCode))\(body)")
        }
        return try parseModelIDs(from: data)
    }
}
