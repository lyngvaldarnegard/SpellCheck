import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Helpers for turning a user-entered API base URL into concrete endpoint URLs.
public enum APIEndpoint {
    public static let defaultBaseURL = "https://api.openai.com/v1"

    /// Normalizes a base URL: trims whitespace, falls back to the default when
    /// empty, and strips trailing slashes.
    public static func baseURL(_ raw: String, default defaultValue: String = defaultBaseURL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: trimmed.isEmpty ? defaultValue : trimmed) else { return nil }
        while url.path.hasSuffix("/") {
            url.deleteLastPathComponent()
        }
        return url
    }

    public static func chatCompletionsURL(_ raw: String) -> URL? {
        guard var url = baseURL(raw), !url.path.hasSuffix("/chat/completions") else {
            return baseURL(raw)
        }
        url.appendPathComponent("chat/completions")
        return url
    }

    public static func modelsURL(_ raw: String) -> URL? {
        guard var url = baseURL(raw), !url.path.hasSuffix("/models") else {
            return baseURL(raw)
        }
        url.appendPathComponent("models")
        return url
    }
}
