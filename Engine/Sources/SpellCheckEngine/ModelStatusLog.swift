import Foundation

/// Remembers, for the current app session, which model answered last and
/// which models failed on their latest attempt, so Settings can explain why a
/// model has no timing. Holds no user text and nothing is written to disk.
public final class ModelStatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String: String] = [:]
    private var answered: String?

    public init() {}

    /// Records one attempt. A nil `failure` means the model answered.
    public func record(model: String, failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let failure {
            failures[model] = failure
        } else {
            failures[model] = nil
            answered = model
        }
    }

    public func lastFailure(for model: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return failures[model]
    }

    public var lastAnsweringModel: String? {
        lock.lock()
        defer { lock.unlock() }
        return answered
    }

    /// Forgets everything, e.g. after the API key or address changed.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        failures = [:]
        answered = nil
    }
}
