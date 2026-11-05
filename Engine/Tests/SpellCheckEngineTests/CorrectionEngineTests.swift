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

    func correct(text: String, prompt: String) async throws -> String {
        recordedPrompt = prompt
        recordedText = text
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

    @Test func unchangedResultSkipsReplace() async {
        let source = FakeSource()
        source.scope = .selection("already fine")
        let backend = FakeBackend()
        backend.response = "already fine"
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(source.replacedWith == nil)
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
            func correct(text: String, prompt: String) async throws -> String { "" }
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
            func correct(text: String, prompt: String) async throws -> String {
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

        #expect(recorder.events.last == .failed("Could not replace the text in the original app"))
    }

    @Test func lostTargetIsReportedWithAppName() async {
        let source = FakeSource()
        source.replaceError = TextSourceError.targetUnavailable("Notion")
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(prompt: prompt)

        #expect(recorder.events.last == .failed("Notion can no longer be used as the target — the original selection is gone. Re-select the text and try again."))
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
        await engine.run(prompt: prompt) // ignored while busy
        #expect(source.grabCallCount == 1)
        #expect(await engine.isBusy == true)
        source.finish()
        await task
        #expect(source.grabCallCount == 1)
    }
}

extension EngineEvent {
    fileprivate var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
