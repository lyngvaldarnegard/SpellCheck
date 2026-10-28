import Foundation
import SpellCheckCore

/// Persists `Settings` as JSON. Kept UI-agnostic so the app layer and tests
/// share the same store.
public actor SettingsStore {
    private let url: URL
    private var cache: Settings

    public init(url: URL) throws {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.cache = decoded
        } else {
            self.cache = .default
        }
    }

    /// Convenience store rooted at the given directory (usually the app's
    /// Application Support directory). Creates the directory when needed.
    public init(directory: URL, fileName: String = "settings.json") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.init(url: directory.appendingPathComponent(fileName))
    }

    public func load() -> Settings { cache }

    public func update(_ transform: (inout Settings) -> Void) throws {
        var next = cache
        transform(&next)
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: .atomic)
        cache = next
    }
}
