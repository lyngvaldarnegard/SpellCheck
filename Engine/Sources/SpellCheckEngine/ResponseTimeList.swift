import Foundation

/// The rows of the Response Times list in Settings.
public enum ResponseTimeList {

    public struct Row: Equatable, Sendable, Identifiable {
        public let model: String
        /// Nil until the model has answered at least one request.
        public let statistics: ResponseTimeEstimator.ModelStatistics?
        public var id: String { model }
    }

    /// With a whitelist, every whitelisted model gets exactly one row, in the
    /// order `RankedModelBackend` tries them: models without a timing first
    /// (in whitelist order), then timed models, fastest first. Without a
    /// whitelist, every timed model is listed as ranked by the estimator.
    public static func rows(
        whitelist: [String],
        statistics: [ResponseTimeEstimator.ModelStatistics]
    ) -> [Row] {
        var seen = Set<String>()
        let models = whitelist
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !models.isEmpty else {
            return statistics.map { Row(model: $0.model, statistics: $0) }
        }
        let byModel = Dictionary(statistics.map { ($0.model, $0) }, uniquingKeysWith: { first, _ in first })
        let untimed = models
            .filter { byModel[$0] == nil }
            .map { Row(model: $0, statistics: nil) }
        let timed = models.enumerated()
            .compactMap { entry in byModel[entry.element].map { (index: entry.offset, stat: $0) } }
            .sorted {
                if $0.stat.interQuartileMeanSeconds != $1.stat.interQuartileMeanSeconds {
                    return $0.stat.interQuartileMeanSeconds < $1.stat.interQuartileMeanSeconds
                }
                return $0.index < $1.index
            }
            .map { Row(model: $0.stat.model, statistics: $0.stat) }
        return untimed + timed
    }
}
