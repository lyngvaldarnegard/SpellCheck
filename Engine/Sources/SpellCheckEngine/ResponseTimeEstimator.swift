import Foundation

/// Learns how long the AI takes to answer and produces estimates for the
/// circular progress indicator.
///
/// One sample is recorded per successful request: the captured text's length
/// and the observed response time, attributed to the model that served it.
/// The estimate assumes response time scales roughly with input length
/// (the user's observation) and uses the MEDIAN seconds-per-character rate of
/// that model's recent samples, so one slow outlier cannot distort the
/// estimate. Samples persist across launches in a small JSON file; nothing
/// sensitive (no text, no prompts, no keys) is ever stored — only numbers.
public final class ResponseTimeEstimator: @unchecked Sendable {

    private struct Sample: Codable {
        let length: Int
        let seconds: Double
    }

    private struct Store: Codable {
        var models: [String: [Sample]] = [:]
    }

    /// Most recent samples kept per model.
    private static let maxSamplesPerModel = 20
    /// Estimates are clamped to a sane range (the request timeout is 120 s).
    private static let minimumEstimate: Double = 0.5
    private static let maximumEstimate: Double = 120

    private let lock = NSLock()
    private var store: Store
    private let fileURL: URL?

    /// - Parameters:
    ///   - fileURL: where samples persist. Nil keeps samples in memory only
    ///     (used by tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            self.store = decoded
        } else {
            self.store = Store()
        }
    }

    /// Records one observed request duration.
    public func record(model: String, inputLength: Int, seconds: Double) {
        guard seconds > 0, inputLength >= 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        var samples = store.models[model] ?? []
        samples.append(Sample(length: inputLength, seconds: seconds))
        if samples.count > Self.maxSamplesPerModel {
            samples.removeFirst(samples.count - Self.maxSamplesPerModel)
        }
        store.models[model] = samples
        persist()
    }

    /// Estimated response time in seconds for a request of the given length,
    /// or nil when this model has no samples yet (the caller then falls back
    /// to one full ring revolution per second).
    public func estimate(model: String, inputLength: Int) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard var samples = store.models[model], !samples.isEmpty else { return nil }
        if samples.count > Self.maxSamplesPerModel {
            samples.removeFirst(samples.count - Self.maxSamplesPerModel)
        }
        // Median seconds-per-character rate, scaled to this request's length.
        let rates = samples
            .map { $0.seconds / Double(max($0.length, 1)) }
            .sorted()
        let mid = rates.count / 2
        let medianRate = rates.count % 2 == 1
            ? rates[mid]
            : (rates[mid - 1] + rates[mid]) / 2
        let estimate = medianRate * Double(max(inputLength, 1))
        return min(max(estimate, Self.minimumEstimate), Self.maximumEstimate)
    }

    private func persist() {
        guard let fileURL else { return }
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
