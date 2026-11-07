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

// MARK: Response-time estimation

struct ResponseTimeEstimatorTests {

    @Test func noSamplesYieldsNoEstimate() {
        let estimator = ResponseTimeEstimator(fileURL: nil)
        #expect(estimator.estimate(model: "mistral-small-latest", inputLength: 100) == nil)
    }

    @Test func estimateScalesWithInputLength() {
        let estimator = ResponseTimeEstimator(fileURL: nil)
        // Two samples for the same model: 1000 chars took 2 s, 3000 chars 6 s
        // → ~0.002 s/char → 500 chars ≈ 1 s.
        estimator.record(model: "m", inputLength: 1000, seconds: 2)
        estimator.record(model: "m", inputLength: 3000, seconds: 6)
        let estimate = estimator.estimate(model: "m", inputLength: 500)
        #expect(estimate != nil)
        #expect(abs(estimate! - 1.0) < 0.2)
        // Double the text → roughly double the time.
        let longer = estimator.estimate(model: "m", inputLength: 1000)
        #expect(abs(longer! - 2.0) < 0.4)
    }

    @Test func ownSamplesBeatGlobalFallback() {
        let estimator = ResponseTimeEstimator(fileURL: nil)
        estimator.record(model: "flash", inputLength: 1000, seconds: 1)
        // A model with no samples yet falls back to the rate learned across
        // ALL models (user spec) instead of returning nothing.
        #expect(estimator.estimate(model: "large", inputLength: 1000) != nil)
        #expect(abs(estimator.estimate(model: "large", inputLength: 1000)! - 1.0) < 0.01)
        // The model's own samples take precedence once they exist.
        estimator.record(model: "large", inputLength: 1000, seconds: 10)
        #expect(abs(estimator.estimate(model: "large", inputLength: 1000)! - 10.0) < 0.01)
    }

    @Test func trulyEmptyStoreYieldsNoEstimate() {
        let estimator = ResponseTimeEstimator(fileURL: nil)
        #expect(estimator.estimate(model: "anything", inputLength: 1000) == nil)
    }

    @Test func interQuartileMeanTrimsBothEnds() {
        // 8 samples of rates: the IQM must drop the lowest quarter and the
        // highest quarter, then average the middle half.
        let estimator = ResponseTimeEstimator(fileURL: nil)
        // rates in s/char: 0.001 x2, 0.002 x4, 0.050 x2 (outliers both ends)
        estimator.record(model: "m", inputLength: 1000, seconds: 1)   // 0.001
        estimator.record(model: "m", inputLength: 1000, seconds: 1)   // 0.001
        estimator.record(model: "m", inputLength: 1000, seconds: 2)   // 0.002
        estimator.record(model: "m", inputLength: 1000, seconds: 2)   // 0.002
        estimator.record(model: "m", inputLength: 1000, seconds: 2)   // 0.002
        estimator.record(model: "m", inputLength: 1000, seconds: 2)   // 0.002
        estimator.record(model: "m", inputLength: 1000, seconds: 50)  // 0.050
        estimator.record(model: "m", inputLength: 1000, seconds: 50)  // 0.050
        // IQM keeps the middle four 0.002 rates -> 2 s for 1000 chars.
        let estimate = estimator.estimate(model: "m", inputLength: 1000)
        #expect(abs(estimate! - 2.0) < 0.01)
    }

    @Test func outlierCannotDistortTheEstimate() {
        let estimator = ResponseTimeEstimator(fileURL: nil)
        for _ in 0..<5 { estimator.record(model: "m", inputLength: 100, seconds: 1) }
        estimator.record(model: "m", inputLength: 100, seconds: 60) // one outlier
        // Median rate stays ~1s per 100 chars.
        let estimate = estimator.estimate(model: "m", inputLength: 100)
        #expect(abs(estimate! - 1.0) < 0.3)
    }

    @Test func samplesPersistAcrossInstances() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-timing-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = ResponseTimeEstimator(fileURL: file)
        first.record(model: "m", inputLength: 1000, seconds: 2)
        let reopened = ResponseTimeEstimator(fileURL: file)
        let estimate = reopened.estimate(model: "m", inputLength: 1000)
        #expect(abs(estimate! - 2.0) < 0.01)
    }

    @Test func statisticsReportMedianIQMAndQuartiles() {
        let estimator = ResponseTimeEstimator(fileURL: nil)
        // Rates in s per 100 tokens (1000 chars = 250 tokens): a sample of
        // S seconds for 1000 chars contributes S * 400/1000 = 0.4*S.
        for seconds in [1.0, 2.0, 2.0, 2.0, 2.0, 3.0, 3.0, 50.0] {
            estimator.record(model: "m", inputLength: 1000, seconds: seconds)
        }
        estimator.record(model: "other", inputLength: 2000, seconds: 4) // 1.6 s/100tok
        let stats = estimator.statistics()
        #expect(stats.count == 2)
        #expect(stats.map(\.model) == ["m", "other"])
        let m = stats.first { $0.model == "m" }!
        #expect(m.sampleCount == 8)
        // Median sample 2.0 s -> 0.8 s per 100 tokens.
        #expect(abs(m.medianSeconds - 0.8) < 0.001)
        // IQM keeps the middle four rates [0.8, 0.8, 0.8, 1.2] -> 0.9.
        #expect(abs(m.interQuartileMeanSeconds - 0.9) < 0.001)
        // Tukey hinges: Q1 = median of lower half = 0.8,
        // Q3 = median of upper half = 1.2.
        #expect(abs(m.firstQuartileSeconds - 0.8) < 0.001)
        #expect(abs(m.thirdQuartileSeconds - 1.2) < 0.001)
    }

    @Test func engineEmitsRequestTimingOnSuccess() async {
        let recorder = EventRecorder()
        let backend = FakeBackend()
        backend.response = "Corrected text"
        let source = FakeSource()
        source.scope = .selection("some selected text")
        let engine = CorrectionEngine(backend: backend, source: source, onEvent: {
            recorder.record($0)
        })

        await engine.run(prompt: Prompt(name: "P", prompt: "p"))

        guard case .requestTiming(let model, let seconds, let inputLength) =
              recorder.events.first(where: { if case .requestTiming = $0 { return true }; return false }) ?? .idle else {
            Issue.record("expected a requestTiming event")
            return
        }
        #expect(model == backend.modelKey)
        #expect(seconds >= 0)
        #expect(inputLength == "some selected text".utf16.count)
    }
}

struct ResponseTimePurgeTests {

    @Test func purgeDropsSamplesForRetiredModels() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("spellcheck-purge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let estimator = ResponseTimeEstimator(fileURL: file)
        estimator.record(model: "mistral-small-latest", inputLength: 1000, seconds: 2)
        estimator.record(model: "old-retired-model", inputLength: 1000, seconds: 5)
        // The provider now serves only these:
        estimator.purgeModels(notIn: ["mistral-small-latest", "mistral-medium-latest"])
        #expect(estimator.estimate(model: "mistral-small-latest", inputLength: 1000) != nil)
        // The retired model's OWN samples are gone (it no longer appears in
        // the tracked models); an estimate for it now comes only from the
        // all-models fallback — and it would never be called anyway, because
        // the UI removes retired models from the whitelist at the same time.
        #expect(estimator.statistics().map(\.model) == ["mistral-small-latest"])
        // Purging everything leaves no data at all.
        estimator.purgeModels(notIn: [])
        #expect(estimator.statistics().isEmpty)
        #expect(estimator.estimate(model: "mistral-small-latest", inputLength: 1000) == nil)
        // The purge persisted: a fresh instance sees the same state.
        let reopened = ResponseTimeEstimator(fileURL: file)
        #expect(reopened.statistics().isEmpty)
    }
}
