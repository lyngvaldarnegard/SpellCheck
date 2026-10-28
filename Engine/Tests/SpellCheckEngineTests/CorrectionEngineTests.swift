import Foundation
import Testing
import SpellCheckCore
@testable import SpellCheckEngine

private final class FakeBackend: CorrectionBackend, @unchecked Sendable {
    let displayName = "Fake"
    let isReady = true
    var response: String = "Corrected text"
    var recordedAction: BuiltinAction?
    var recordedCustomPrompt: String?
    var recordedLanguage: String?

    func correct(text: String, action: BuiltinAction, customPrompt: String?, language: String?) async throws -> String {
        recordedAction = action
        recordedCustomPrompt = customPrompt
        recordedLanguage = language
        return response
    }
}

private final class FakeSource: TextSource, @unchecked Sendable {
    var scope: TextScope = .selection("original text")
    var replacedWith: String?
    var replaceSucceeds = true
    var error: (any Error)?

    func grab() async throws -> GrabbedText {
        if let error { throw error }
        return GrabbedText(scope: scope) { [weak self] newText in
            self?.replacedWith = newText
            return self?.replaceSucceeds ?? false
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
        confirm: @escaping CorrectionEngine.ConfirmHandler = { _, _ in true },
        recorder: EventRecorder
    ) -> CorrectionEngine {
        CorrectionEngine(backend: backend, source: source, confirm: confirm, onEvent: { event in
            recorder.record(event)
        })
    }

    @Test func happyPathReplacesText() async {
        let recorder = EventRecorder()
        let backend = FakeBackend()
        let source = FakeSource()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .fixTypos)

        #expect(source.replacedWith == "Corrected text")
        #expect(recorder.events.first == .working("Correcting…"))
        #expect(recorder.events.last == .succeeded("Corrected text"))
        #expect(await engine.isBusy == false)
    }

    @Test func passesCustomPromptThrough() async {
        let backend = FakeBackend()
        let source = FakeSource()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .fixTypos, customPrompt: "make it pirate talk")

        #expect(backend.recordedCustomPrompt == "make it pirate talk")
    }

    @Test func passesTranslationLanguageThrough() async {
        let backend = FakeBackend()
        let source = FakeSource()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .translate, language: "German")

        #expect(backend.recordedAction == .translate)
        #expect(backend.recordedLanguage == "German")
        #expect(recorder.events.first == .working("Translating…"))
    }

    @Test func unchangedResultSkipsReplace() async {
        let source = FakeSource()
        source.scope = .selection("already fine")
        let backend = FakeBackend()
        backend.response = "already fine"
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .fixTypos)

        #expect(source.replacedWith == nil)
        #expect(recorder.events.last == .succeeded("already fine"))
    }

    @Test func declinedConfirmationKeepsOriginal() async {
        let source = FakeSource()
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, confirm: { _, _ in false }, recorder: recorder)

        await engine.run(action: .fixTypos)

        #expect(source.replacedWith == nil)
        #expect(recorder.events.last == .idle)
    }

    @Test func emptyGrabReportsFailure() async {
        let source = FakeSource()
        source.scope = .selection("   ")
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .fixTypos)

        #expect(recorder.events.last == .failed("There is no text to work on"))
    }

    @Test func backendErrorIsReported() async {
        final class ThrowingBackend: CorrectionBackend, @unchecked Sendable {
            let displayName = "Throwing"
            let isReady = true
            func correct(text: String, action: BuiltinAction, customPrompt: String?, language: String?) async throws -> String {
                throw CorrectionError.backendFailed("API request failed with status 401")
            }
        }
        let source = FakeSource()
        let recorder = EventRecorder()
        let engine = CorrectionEngine(backend: ThrowingBackend(), source: source, onEvent: { event in
            recorder.record(event)
        })

        await engine.run(action: .fixTypos)

        #expect(recorder.events.last == .failed("API request failed with status 401"))
    }

    @Test func sourceErrorIsReported() async {
        let source = FakeSource()
        source.error = TextSourceError.noText
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .fixTypos)

        #expect(recorder.events.last?.isFailure == true)
    }

    @Test func replaceFailureIsReported() async {
        let source = FakeSource()
        source.replaceSucceeds = false
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = makeEngine(backend: backend, source: source, recorder: recorder)

        await engine.run(action: .fixTypos)

        #expect(recorder.events.last == .failed("Could not replace the text in the frontmost app"))
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
                return GrabbedText(scope: .selection("text")) { _ in true }
            }

            func finish() { release?() }
        }
        let source = BlockingSource()
        let backend = FakeBackend()
        let recorder = EventRecorder()
        let engine = CorrectionEngine(backend: backend, source: source, onEvent: { event in
            recorder.record(event)
        })
        let task = Task { await engine.run(action: .fixTypos) }
        while await !engine.isBusy {
            await Task.yield()
        }
        await engine.run(action: .fixTypos) // ignored while busy
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
