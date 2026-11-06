import Foundation
import Testing
import SpellCheckCore
@testable import SpellCheckEngine

private final class FakeBackend: CorrectionBackend, @unchecked Sendable {
    let displayName = "Fake"
    let isReady = true
    var response: String = "Corrected text"
    var recordedPrompt: String?
    var recordedText: String?
    var recordedSharedPrompt: String?

    func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
        recordedPrompt = prompt
        recordedText = text
        recordedSharedPrompt = sharedPrompt
        return response
    }
}

private final class FakeSource: TextSource, @unchecked Sendable {
    var scope: TextScope = .selection("original text")
    var replacedWith: String?
    var replaceError: (any Error)?
    var error: (any Error)?

    func grab() async throws -> GrabbedText {
        if let error { throw error }
        return GrabbedText(scope: scope) { [weak self] newText in
            if let replaceError = self?.replaceError { throw replaceError }
            self?.replacedWith = newText
        }
    }
}

private final class EventRecorder: @unchecked Sendable {
    var events: [EngineEvent] = []
    func record(_ event: EngineEvent) {
        events.append(event)
    }
}

struct CorrectionEngineTests {

    private func makeEngine(
        backend: FakeBackend,
        source: FakeSource,
        recorder: EventRecorder
    ) -> CorrectionEngine {
        CorrectionEngine(backend: backend, source: source, onEvent: { event in
            recorder.record(event)
        })
    }

    private let prompt = Prompt(name: "Fix Grammar", prompt: "Fix grammar only")

    @Test func happyPathReplacesTextWithoutConfirmation() async {
        let recorder = EventRecorder()
        let backend = FakeBackend()
        let source = FakeSource()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(source.replacedWith == "Corrected text")
        #expect(backend.recordedPrompt == "Fix grammar only")
        #expect(backend.recordedText == "original text")
        #expect(recorder.events.first == .working("Running “Fix Grammar”…"))
        #expect(recorder.events.last == .succeeded("Corrected text"))
        #expect(await engine.isBusy == false)
    }

    @Test func runOnPreGrabbedTextUsesProvidedSelection() async {
        let recorder = EventRecorder()
        let backend = FakeBackend()
        let source = FakeSource()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        let grabbed = GrabbedText(scope: .selection("captured earlier")) { newText in
            source.replacedWith = newText
        }
        await engine.run(prompt: prompt, on: grabbed)

        #expect(backend.recordedText == "captured earlier")
        #expect(source.replacedWith == "Corrected text")
    }

    @Test func identicalResultStillReplacesAsConfirmation() async {
        let source = FakeSource()
        source.scope = .selection("already fine")
        let backend = FakeBackend()
        backend.response = "already fine"
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        // The identical text is written back too — the visible replacement is
        // the user's confirmation that the workflow ran.
        #expect(source.replacedWith == "already fine")
        #expect(recorder.events.last == .succeeded("already fine"))
    }

    @Test func emptyGrabReportsFailure() async {
        let source = FakeSource()
        source.scope = .selection("   ")
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .failed("There is no text to work on"))
        #expect(backend.recordedPrompt == nil)
    }

    @Test func unconfiguredBackendReportsFailure() async {
        final class UnconfiguredBackend: CorrectionBackend, @unchecked Sendable {
            let displayName = "Unconfigured"
            let isReady = false
            func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String { "" }
        }
        let source = FakeSource()
        let recorder = EventRecorder()
        let engine = CorrectionEngine(backend: UnconfiguredBackend(), source: source, onEvent: {
            recorder.record($0)
        })

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .failed("No API key configured — add one in SpellCheck Settings"))
        #expect(source.replacedWith == nil)
    }

    @Test func backendErrorIsReported() async {
        final class ThrowingBackend: CorrectionBackend, @unchecked Sendable {
            let displayName = "Throwing"
            let isReady = true
            func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
                throw CorrectionError.backendFailed("API request failed with status 401")
            }
        }
        let source = FakeSource()
        let recorder = EventRecorder()
        let engine = CorrectionEngine(backend: ThrowingBackend(), source: source, onEvent: {
            recorder.record($0)
        })

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .failed("API request failed with status 401"))
    }

    @Test func sharedPromptIsPassedToBackend() async {
        let recorder = EventRecorder()
        let backend = FakeBackend()
        let source = FakeSource()
        let engine = CorrectionEngine(
            backend: backend,
            source: source,
            sharedPrompt: "Always answer in the text's original language.",
            onEvent: { recorder.record($0) }
        )

        await engine.run(prompt: prompt)

        #expect(backend.recordedSharedPrompt == "Always answer in the text's original language.")
        #expect(backend.recordedPrompt == "Fix grammar only")
        #expect(backend.recordedText == "original text")
    }

    @Test func sourceErrorIsReported() async {
        let source = FakeSource()
        source.error = TextSourceError.noText
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last?.isFailure == true)
    }

    @Test func replaceFailureIsReported() async {
        let source = FakeSource()
        source.replaceError = TextSourceError.replaceFailed
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .replaceFailed("Could not replace the text in the original app — nothing was changed. Re-select the text and try again."))
    }

    @Test func changedSelectionIsReportedWithoutTouchingText() async {
        let source = FakeSource()
        source.replaceError = TextSourceError.selectionChanged("TextEdit")
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .replaceFailed("The original selection is no longer intact in TextEdit, so nothing was replaced. Re-select the text and try again."))
    }

    @Test func unverifiedReplacementIsReportedHonestly() async {
        let source = FakeSource()
        source.replaceError = TextSourceError.unverified("Notion")
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .replaceFailed("The correction was pasted into Notion, but SpellCheck could not verify the result — please check the text (⌘Z undoes it if needed). The corrected text is also on the clipboard."))
    }

    @Test func lostTargetIsReportedWithAppName() async {
        let source = FakeSource()
        source.replaceError = TextSourceError.targetUnavailable("Notion")
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .replaceFailed("Notion can no longer be used as the target — the original selection is gone. Re-select the text and try again."))
    }

    @Test func busyEngineIgnoresSecondRun() async {
        final class BlockingSource: TextSource, @unchecked Sendable {
            private(set) var grabCallCount = 0
            private var release: (() -> Void)?

            func grab() async throws -> GrabbedText {
                grabCallCount += 1
                await withCheckedContinuation { continuation in
                    release = { continuation.resume() }
                }
                return GrabbedText(scope: .selection("text")) { _ in }
            }

            func finish() { release?() }
        }
        let source = BlockingSource()
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = CorrectionEngine(backend: backend, source: source, onEvent: {
            recorder.record($0)
        })
        let task = Task { await engine.run(prompt: prompt) }
        while await !engine.isBusy {
            await Task.yield()
        }
        await engine.run(prompt: prompt) // rejected while busy
        #expect(source.grabCallCount == 1)
        #expect(await engine.isBusy == true)
        // The rejected run is NOT silent: a busy event tells the user, and no
        // duplicate request or replacement was started.
        #expect(recorder.events.contains { 
            if case .busy = $0 { return true }
            return false
        })
        source.finish()
        await task
        #expect(source.grabCallCount == 1)
    }

    @Test func busyEngineRejectsPreGrabbedRunWithEventAndNeverReplaces() async {
        final class BlockingBackend: CorrectionBackend, @unchecked Sendable {
            let displayName = "Blocking"
            let isReady = true
            private var release: (() -> Void)?
            func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
                await withCheckedContinuation { continuation in
                    release = { continuation.resume(returning: "Corrected text") }
                }
                return "Corrected text"
            }
            func finish() { release?() }
        }
        let backend = BlockingBackend()
        let source = FakeSource()
        let recorder = EventRecorder()
        let engine = CorrectionEngine(backend: backend, source: source, onEvent: {
            recorder.record($0)
        })
        final class Flag: @unchecked Sendable { var value = false }
        let firstReplaced = Flag()
        let first = GrabbedText(scope: .selection("first text")) { _ in
            firstReplaced.value = true
        }
        let second = GrabbedText(scope: .selection("second text")) { newText in
            Issue.record("a rejected busy run must never replace anything (got \(newText))")
        }
        let task = Task { await engine.run(prompt: prompt, on: first) }
        while await !engine.isBusy {
            await Task.yield()
        }
        await engine.run(prompt: prompt, on: second) // rejected while busy
        #expect(recorder.events.contains {
            if case .busy = $0 { return true }
            return false
        })
        backend.finish()
        await task.value
        #expect(firstReplaced.value)
    }
}

extension EngineEvent {
    fileprivate var isFailure: Bool {
        switch self {
        case .failed, .replaceFailed: return true
        default: return false
        }
    }
}
