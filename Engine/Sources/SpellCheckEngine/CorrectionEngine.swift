import Foundation
import SpellCheckCore

/// Coarse-grained progress events, suitable for driving a menu-bar status line.
public enum EngineEvent: Sendable, Equatable {
    case idle
    case working(String)
    case succeeded(String)
    case failed(String)
}

/// Orchestrates one correction run: grab text, ask the backend, optionally
/// confirm with the user, then swap the result back in. UI-agnostic so it can
/// be unit tested with fake sources and backends.
public actor CorrectionEngine {
    public typealias ConfirmHandler = @Sendable (String, String) async -> Bool
    public typealias EventHandler = @Sendable (EngineEvent) -> Void

    private let backend: any CorrectionBackend
    private let source: any TextSource
    private let confirmHandler: ConfirmHandler
    private let eventHandler: EventHandler

    public private(set) var isBusy: Bool = false

    public init(
        backend: any CorrectionBackend,
        source: any TextSource,
        confirm: @escaping ConfirmHandler = { _, _ in true },
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.backend = backend
        self.source = source
        self.confirmHandler = confirm
        self.eventHandler = onEvent
    }

    /// Runs one correction. Concurrent calls are ignored while a run is busy.
    public func run(action: BuiltinAction, customPrompt: String? = nil, language: String? = nil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        eventHandler(.working(action == .translate ? "Translating…" : "Correcting…"))
        do {
            let grabbed = try await source.grab()
            let original = grabbed.scope.text
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                eventHandler(.failed("There is no text to work on"))
                return
            }
            let response = try await backend.correct(
                text: original,
                action: action,
                customPrompt: customPrompt,
                language: language
            )
            let corrected = ResponseCleaner.clean(response, input: original)
            guard !corrected.isEmpty else {
                eventHandler(.failed("The backend returned an empty result"))
                return
            }
            guard corrected != original else {
                eventHandler(.succeeded(corrected))
                return
            }
            guard await confirmHandler(original, corrected) else {
                eventHandler(.idle)
                return
            }
            eventHandler(.working("Replacing…"))
            let replaced = await grabbed.replace(corrected)
            eventHandler(replaced
                ? .succeeded(corrected)
                : .failed("Could not replace the text in the frontmost app"))
        } catch {
            eventHandler(.failed(Self.message(for: error)))
        }
    }

    public static func message(for error: Error) -> String {
        if let correctionError = error as? CorrectionError {
            switch correctionError {
            case .notConfigured:
                return "The correction backend is not configured"
            case .emptyResponse:
                return "The backend returned an empty result"
            case .backendFailed(let message):
                return message
            case .cancelled:
                return "Cancelled"
            }
        }
        if let sourceError = error as? TextSourceError {
            switch sourceError {
            case .noText:
                return "No text found — select some text or place the caret inside a sentence"
            case .accessDenied:
                return "SpellCheck needs Accessibility permission (System Settings → Privacy & Security → Accessibility)"
            case .replaceFailed:
                return "Could not replace the text in the frontmost app"
            }
        }
        return error.localizedDescription
    }
}
