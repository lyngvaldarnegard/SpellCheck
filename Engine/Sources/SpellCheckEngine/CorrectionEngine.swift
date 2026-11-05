import Foundation
import SpellCheckCore

/// Coarse-grained progress events, suitable for driving a menu-bar status line.
public enum EngineEvent: Sendable, Equatable {
    case idle
    case working(String)
    case succeeded(String)
    case failed(String)
}

/// Orchestrates one AI edit: grab text, ask the backend, then swap the result
/// back in — no confirmation step in between. UI-agnostic so it can be unit
/// tested with fake sources and backends.
public actor CorrectionEngine {
    public typealias EventHandler = @Sendable (EngineEvent) -> Void

    private let backend: any CorrectionBackend
    private let source: any TextSource
    private let eventHandler: EventHandler

    private var busy = false

    /// True while an edit is in flight.
    public var isBusy: Bool { busy }

    public init(
        backend: any CorrectionBackend,
        source: any TextSource,
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.backend = backend
        self.source = source
        self.eventHandler = onEvent
    }

    /// Runs one edit with the given prompt. Concurrent calls are ignored while
    /// a run is busy. The text is grabbed from the source when the run starts.
    public func run(prompt: Prompt) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let grabbed = try await source.grab()
            try await perform(prompt: prompt, on: grabbed)
        } catch {
            eventHandler(.failed(Self.message(for: error)))
        }
    }

    /// Runs one edit on text that was already grabbed (e.g. when the prompt
    /// picker captured the selection before opening). Keeps the original
    /// selection and target application for the whole run.
    public func run(prompt: Prompt, on grabbed: GrabbedText) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await perform(prompt: prompt, on: grabbed)
        } catch {
            eventHandler(.failed(Self.message(for: error)))
        }
    }

    private func perform(prompt: Prompt, on grabbed: GrabbedText) async throws {
        eventHandler(.working("Running “\(prompt.name)”…"))
        guard backend.isReady else { throw CorrectionError.notConfigured }
        let original = grabbed.scope.text
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            eventHandler(.failed("There is no text to work on"))
            return
        }
        let response = try await backend.correct(text: original, prompt: prompt.prompt)
        let corrected = ResponseCleaner.clean(response, input: original)
        guard !corrected.isEmpty else {
            eventHandler(.failed("The API returned an empty result"))
            return
        }
        guard corrected != original else {
            eventHandler(.succeeded(corrected))
            return
        }
        eventHandler(.working("Replacing…"))
        do {
            try await grabbed.replace(corrected)
            eventHandler(.succeeded(corrected))
        } catch {
            eventHandler(.failed(Self.message(for: error)))
        }
    }

    public static func message(for error: Error) -> String {
        if let correctionError = error as? CorrectionError {
            switch correctionError {
            case .notConfigured:
                return "No API key configured — add one in SpellCheck Settings"
            case .emptyResponse:
                return "The API returned an empty result"
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
                return "Could not replace the text in the original app — nothing was changed. Re-select the text and try again."
            case .targetUnavailable(let appName):
                return "\(appName) can no longer be used as the target — the original selection is gone. Re-select the text and try again."
            case .selectionChanged(let appName):
                return "The original selection is no longer intact in \(appName), so nothing was replaced. Re-select the text and try again."
            case .unverified(let appName):
                return "The correction was pasted into \(appName), but SpellCheck could not verify the result — please check the text (⌘Z undoes it if needed). The corrected text is also on the clipboard."
            }
        }
        return error.localizedDescription
    }
}
