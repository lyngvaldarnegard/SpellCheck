import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Helpers for turning a user-entered API base URL into concrete endpoint URLs.
public enum APIEndpoint {
    public static let defaultBaseURL = "https://api.openai.com/v1"

    /// Normalizes a base URL string: trims whitespace, falls back to the
    /// default when empty, and strips trailing slashes. Returns nil when the
    /// result is not a valid http(s) URL.
    public static func normalizeBaseURL(_ raw: String, fallback: String = defaultBaseURL) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed.isEmpty ? fallback : trimmed
        while candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return candidate
    }

    public static func baseURL(_ raw: String, fallback: String = defaultBaseURL) -> URL? {
        guard let normalized = normalizeBaseURL(raw, fallback: fallback) else { return nil }
        return URL(string: normalized)
    }

    public static func chatCompletionsURL(_ raw: String) -> URL? {
        guard let base = normalizeBaseURL(raw) else { return nil }
        if base.hasSuffix("/chat/completions") {
            return URL(string: base)
        }
        return URL(string: base + "/chat/completions")
    }

    public static func modelsURL(_ raw: String) -> URL? {
        guard let base = normalizeBaseURL(raw) else { return nil }
        if base.hasSuffix("/models") {
            return URL(string: base)
        }
        return URL(string: base + "/models")
    }
}
