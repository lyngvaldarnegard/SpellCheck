import Foundation

/// A backend that turns input text into edited text via an AI API.
public protocol CorrectionBackend: Sendable {
    /// Human readable backend name shown in the UI.
    var displayName: String { get }
    /// Whether the backend is ready to serve requests (credentials present, etc.).
    var isReady: Bool { get }

    /// Edits `text` according to the user prompt's instruction text.
    func correct(text: String, prompt: String) async throws -> String
}

/// Errors a backend can throw.
public enum CorrectionError: Error, Equatable, Sendable {
    case notConfigured
    case emptyResponse
    case backendFailed(String)
    case cancelled
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
