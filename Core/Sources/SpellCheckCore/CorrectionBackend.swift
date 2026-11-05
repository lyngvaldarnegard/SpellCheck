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

/// Trims a backend response: some models wrap the answer in quotes or repeat
/// the "Text:" framing despite instructions.
public enum ResponseCleaner {
    public static func clean(_ response: String, input: String) -> String {
        var text = response
        // Strip a single layer of surrounding quotes if the whole answer is quoted.
        if text.count >= 2,
           (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("\u{201c}") && text.hasSuffix("\u{201d}")) {
            text.removeFirst()
            text.removeLast()
        }
        // Some models echo the input back when confused; never return text
        // identical to the input plus framing.
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == input { return text }
        return text
    }
}
