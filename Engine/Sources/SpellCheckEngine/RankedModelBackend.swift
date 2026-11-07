import Foundation
import SpellCheckCore

/// Serves each request from a user-approved whitelist of models, ordered by
/// learned speed: the model with the fastest estimated response time serves
/// the request; if it fails for a retryable reason (capacity, rate limit,
/// server error, timeout, unusable response), the next fastest is tried, and
/// so on. The user chooses which models are acceptable (quality/cost); the
/// app chooses which one to actually use (speed), from its own measured data.
///
/// The ranking is recomputed per request from the estimator, so it always
/// reflects the newest learned times. Ranking is independent of the request
/// size (all models scale with the same text), so a fixed reference length is
/// used. Models with no samples inherit the all-models average via the
/// estimator's fallback; a completely empty store keeps the whitelist order.
public final class RankedModelBackend: CorrectionBackend, @unchecked Sendable {

    private let models: [String]
    private let makeBackend: (String) -> any CorrectionBackend
    private let estimatedSeconds: (String) -> Double?
    private let lock = NSLock()
    private var lastServingModel: String?

    /// - Parameters:
    ///   - models: the user's whitelist, in their chosen order (the tiebreak
    ///     for models with equal estimates).
    ///   - makeBackend: builds a concrete backend for one model id.
    ///   - estimatedSeconds: learned response-time estimate for one model at
    ///     a fixed reference length (nil = no data at all).
    public init(
        models: [String],
        makeBackend: @escaping (String) -> any CorrectionBackend,
        estimatedSeconds: @escaping (String) -> Double?
    ) {
        self.models = models
        self.makeBackend = makeBackend
        self.estimatedSeconds = estimatedSeconds
    }

    public var displayName: String { "Ranked model whitelist" }

    public var isReady: Bool {
        models.contains { makeBackend($0).isReady }
    }

    /// The model that served the last request (for response-time
    /// attribution); before the first request, the model that would be
    /// tried first.
    public var modelKey: String {
        lock.lock()
        let last = lastServingModel
        lock.unlock()
        if let last { return last }
        return rankedModels().first ?? ""
    }

    public func correct(text: String, prompt: String, sharedPrompt: String) async throws -> String {
        let ordered = rankedModels()
        guard !ordered.isEmpty else { throw CorrectionError.notConfigured }
        var lastError: Error = CorrectionError.notConfigured
        for model in ordered {
            do {
                let result = try await makeBackend(model).correct(text: text, prompt: prompt, sharedPrompt: sharedPrompt)
                recordServing(model)
                return result
            } catch {
                lastError = error
                guard FallbackPolicy.shouldFallback(after: error) else { throw error }
                // Retryable: try the next fastest whitelisted model.
            }
        }
        throw CorrectionError.backendFailed(
            "None of the whitelisted models could serve the request: \(CorrectionEngine.message(for: lastError))"
        )
    }

    /// NSLock is unavailable in async contexts; this synchronous helper is.
    private func recordServing(_ model: String) {
        lock.lock()
        lastServingModel = model
        lock.unlock()
    }

    /// Whitelist ordered by learned speed (fastest first). Swift's sort is
    /// not stable, so the whitelist index breaks ties explicitly.
    private func rankedModels() -> [String] {
        let ranked = models.enumerated().map { entry -> (index: Int, model: String, seconds: Double) in
            (entry.offset, entry.element, estimatedSeconds(entry.element) ?? .infinity)
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return lhs.index < rhs.index
            }
            .map(\.model)
    }
}
