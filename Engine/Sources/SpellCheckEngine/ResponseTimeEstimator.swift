import Foundation

/// Learns how long the AI takes to answer and produces estimates for the
/// circular progress indicator.
///
/// One sample is recorded per successful request: the captured text's length
/// and the observed response time, attributed to the model that served it.
/// The estimate assumes response time scales roughly with input length
/// (the user's observation) and uses the INTER-QUARTILE MEAN (IQM) of the
/// seconds-per-character rates: the top and bottom quarters of the sorted
/// rates are discarded and the middle half is averaged. This uses more of
/// the data than a plain median (smoother estimates) while still trimming
/// slow outliers (network stalls, capacity hiccups). Samples persist across
/// launches in a small JSON file; nothing sensitive (no text, no prompts,
/// no keys) is ever stored — only numbers.
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

    /// Learned response-time statistics for one model, shown in Settings.
    /// All times are normalized to seconds per 1000 characters so samples of
    /// different text lengths are comparable.
    public struct ModelStatistics: Equatable, Sendable {
        public let model: String
        public let sampleCount: Int
        public let medianSeconds: Double
        public let interQuartileMeanSeconds: Double
        public let firstQuartileSeconds: Double
        public let thirdQuartileSeconds: Double
    }

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

    /// Estimated response time in seconds for a request of the given length.
    /// Uses this model's own samples; a model with no samples yet falls back
    /// to the rate learned across ALL recorded models (per the user's spec),
    /// so only the very first requests ever — with no data at all — return
    /// nil (the caller then uses one full ring revolution per second).
    public func estimate(model: String, inputLength: Int) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let own = store.models[model] ?? []
        let fallback = own.isEmpty
            ? store.models.values.flatMap { $0 }.suffix(Self.maxSamplesPerModel)
            : []
        let samples = own.isEmpty ? Array(fallback) : own
        guard !samples.isEmpty else { return nil }
        // Inter-quartile mean of the seconds-per-character rates, scaled to
        // this request's length. With very few samples nothing is trimmed
        // (a plain mean), which is the IQM's natural small-n behavior.
        let rates = samples
            .map { $0.seconds / Double(max($0.length, 1)) }
            .sorted()
        let trim = rates.count / 4
        let kept = trim > 0 ? rates[trim..<(rates.count - trim)] : rates[...]
        let rate = kept.reduce(0, +) / Double(kept.count)
        let estimate = rate * Double(max(inputLength, 1))
        return min(max(estimate, Self.minimumEstimate), Self.maximumEstimate)
    }

    /// Learned statistics for every tracked model, sorted by model name.
    public func statistics() -> [ModelStatistics] {
        lock.lock()
        defer { lock.unlock() }
        return store.models.keys.sorted().map { model in
            let rates = (store.models[model] ?? [])
                .map { $0.seconds / Double(max($0.length, 1)) * 1000 }
                .sorted()
            let kept = Self.interQuartileRange(of: rates)
            return ModelStatistics(
                model: model,
                sampleCount: rates.count,
                medianSeconds: rates.isEmpty ? 0 : Self.median(of: rates),
                interQuartileMeanSeconds: rates.isEmpty ? 0 : Self.mean(of: kept),
                firstQuartileSeconds: rates.isEmpty ? 0 : Self.firstQuartile(of: rates),
                thirdQuartileSeconds: rates.isEmpty ? 0 : Self.thirdQuartile(of: rates)
            )
        }
    }

    // MARK: Rate helpers (seconds per 1000 characters, sorted input required)

    private static func median(of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    private static func mean(of values: ArraySlice<Double>) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func firstQuartile(of sorted: [Double]) -> Double {
        median(of: Array(sorted.prefix((sorted.count + 1) / 2)))
    }

    private static func thirdQuartile(of sorted: [Double]) -> Double {
        median(of: Array(sorted.suffix((sorted.count + 1) / 2)))
    }

    /// The middle half of the sorted rates (the values the IQM averages).
    private static func interQuartileRange(of sorted: [Double]) -> ArraySlice<Double> {
        let trim = sorted.count / 4
        return trim > 0 ? sorted[trim..<(sorted.count - trim)] : sorted[...]
    }

    private func persist() {
        guard let fileURL else { return }
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
