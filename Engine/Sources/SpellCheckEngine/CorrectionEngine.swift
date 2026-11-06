import Foundation
import SpellCheckCore

/// Coarse-grained progress events, suitable for driving a menu-bar status line.
public enum EngineEvent: Sendable, Equatable {
    case idle
    case working(String)
    case succeeded(String)
    /// Alert-worthy failure (API, configuration, permission, save errors).
    case failed(String)
    /// The replacement could not be issued or verified in the target app.
    /// Reported in the menu bar only — the user asked for no intrusive popup
    /// here, and a retry is left to the user. Never triggers another paste.
    case replaceFailed(String)
    /// A new edit was requested while another one is still running. The new
    /// edit is NOT started (no duplicate request, no second paste); the user
    /// is told why instead of the request silently disappearing.
    case busy(String)
}

/// Orchestrates one AI edit: grab text, ask the backend, then swap the result
/// back in — no confirmation step in between. UI-agnostic so it can be unit
/// tested with fake sources and backends.
public actor CorrectionEngine {
    public typealias EventHandler = @Sendable (EngineEvent) -> Void

    private let backend: any CorrectionBackend
    private let source: any TextSource
    private let sharedPrompt: String
    private let eventHandler: EventHandler

    private var busy = false

    /// True while an edit is in flight.
    public var isBusy: Bool { busy }

    public init(
        backend: any CorrectionBackend,
        source: any TextSource,
        sharedPrompt: String = "",
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.backend = backend
        self.source = source
        self.sharedPrompt = sharedPrompt
        self.eventHandler = onEvent
    }

    /// Runs one edit with the given prompt. Concurrent calls are reported via
    /// `.busy` while a run is busy. The text is grabbed from the source when
    /// the run starts.
    public func run(prompt: Prompt) async {
        guard !busy else {
            eventHandler(.busy(Self.busyMessage))
            return
        }
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
        guard !busy else {
            eventHandler(.busy(Self.busyMessage))
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await perform(prompt: prompt, on: grabbed)
        } catch {
            eventHandler(.failed(Self.message(for: error)))
        }
    }

    private static let busyMessage = "A correction is still running — the new prompt was not started. Wait for the current one to finish, then try again."

    private func perform(prompt: Prompt, on grabbed: GrabbedText) async throws {
        eventHandler(.working("Running “\(prompt.name)”…"))
        guard backend.isReady else { throw CorrectionError.notConfigured }
        let original = grabbed.scope.text
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            eventHandler(.failed("There is no text to work on"))
            return
        }
        let response = try await backend.correct(text: original, prompt: prompt.prompt, sharedPrompt: sharedPrompt)
        let corrected = ResponseCleaner.clean(response, input: original)
        guard !corrected.isEmpty else {
            eventHandler(.failed("The API returned an empty result"))
            return
        }
        // An identical result is written back too: the visible replacement is
        // the user's confirmation that the workflow actually ran.
        eventHandler(.working("Replacing…"))
        do {
            try await grabbed.replace(corrected)
            eventHandler(.succeeded(corrected))
        } catch {
            eventHandler(.replaceFailed(Self.message(for: error)))
        }
    }

    public static func message(for error: Error) -> String {
        if let correctionError = error as? CorrectionError {
            switch correctionError {
            case .notConfigured:
                return "No API key configured — add one in SpellCheck Settings"
            case .emptyResponse:
                return "The API returned an empty result"
            case .http(let status, let message):
                return "The API request failed with status \(status): \(message)"
            case .unusableResponse(let message):
                return message
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
