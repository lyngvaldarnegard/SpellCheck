import Foundation

/// A backend that turns input text into edited text via an AI API.
public protocol CorrectionBackend: Sendable {
    /// Human readable backend name shown in the UI.
    var displayName: String { get }
    /// Whether the backend is ready to serve requests (credentials present, etc.).
    var isReady: Bool { get }
    /// Stable key identifying the model(s) this backend talks to, used for
    /// per-model response-time estimation. Backends without a meaningful
    /// model identity fall back to `displayName`.
    var modelKey: String { get }

    /// Edits `text` according to the user prompt's instruction text and the
    /// shared prompt (a common instruction included in every request).
    func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String
}

extension CorrectionBackend {
    /// Default model identity for backends that do not define one.
    public var modelKey: String { displayName }

    /// Backends that have not been updated to the shared-prompt signature yet
    public func correct(text: String, prompt: String) async throws -> String {
        try await correct(text: text, prompt: prompt, sharedPrompt: "")
    }
}

/// Errors a backend can throw.
public enum CorrectionError: Error, Equatable, Sendable {
    case notConfigured
    case emptyResponse
    /// The provider answered with an HTTP error status. `message` is a short,
    /// sanitized summary — never the full response body.
    case http(status: Int, message: String)
    /// The response could not be read or used (unexpected format, missing
    /// content, undecodable payload). The model or endpoint may be incompatible.
    case unusableResponse(String)
    case backendFailed(String)
    case cancelled

    /// Whether a failure of this kind is worth retrying on a backup model:
    /// temporary capacity/rate limits, server errors, timeouts and unusable
    /// responses qualify; configuration and authentication errors do not.
    public var isRetryableWithBackup: Bool {
        switch self {
        case .emptyResponse, .unusableResponse:
            return true
        case .http(let status, _):
            return Self.retryableStatuses.contains(status)
        case .backendFailed, .notConfigured, .cancelled:
            return false
        }
    }

    public static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]
}

/// Whether an error thrown by a backend is worth retrying on a backup model.
public enum FallbackPolicy {
    public static func shouldFallback(after error: Error) -> Bool {
        if let correctionError = error as? CorrectionError {
            return correctionError.isRetryableWithBackup
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }
}

/// Trims a backend response: some models wrap the answer in quotes, echo the
/// `<<<` / `>>>` input markers, or repeat the "Text:" framing despite
/// instructions. Only the exact marker framing is removed — legitimate `<` or
/// `>` characters in the text are always preserved.
public enum ResponseCleaner {
    public static func clean(_ response: String, input: String) -> String {
        var text = response
        // Strip a single layer of surrounding quotes if the whole answer is quoted.
        if text.count >= 2,
           (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("\u{201c}") && text.hasSuffix("\u{201d}")) {
            text.removeFirst()
            text.removeLast()
        }
        text = stripEchoedMarkers(text)
        // Some models echo the input back when confused; never return text
        // identical to the input plus framing.
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == input { return text }
        return text
    }

    /// Removes one layer of the input markers `<<<` / `>>>` when the model
    /// echoes them around its answer (PromptBuilder wraps the input in them).
    /// Handles both the inline form `<<<answer>>>` and the multi-line form
    /// where the first line is `<<<` and the last line is `>>>`. Anything
    /// else — including legitimate angle brackets in the text — is untouched.
    static func stripEchoedMarkers(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Inline wrap: <<<answer>>>
        if trimmed.count >= 6, trimmed.hasPrefix("<<<"), trimmed.hasSuffix(">>>") {
            let inner = String(trimmed.dropFirst(3).dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty {
                return inner
            }
        }
        // Line wrap: first non-empty line is exactly <<<, last is exactly >>>.
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return text }
        let firstNonEmpty = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lastNonEmpty = lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = firstNonEmpty, first.trimmingCharacters(in: .whitespaces) == "<<<",
              let last = lastNonEmpty, last.trimmingCharacters(in: .whitespaces) == ">>>" else { return text }
        if let firstIndex = lines.firstIndex(of: first) {
            lines.remove(at: firstIndex)
        }
        if let lastIndex = lines.lastIndex(of: last) {
            lines.remove(at: lastIndex)
        }
        return lines.joined(separator: "\n")
    }
}
