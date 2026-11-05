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
            // The existing file could not be decoded (corrupt or truncated
            // after an update). Keep a timestamped backup next to it so the
            // user's data — prompts included — is never silently destroyed,
            // then start from defaults.
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.deletingPathExtension()
                    .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: url, to: backup)
            }
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

    public func update(_ transform: @Sendable (Settings) -> Settings) throws {
        let next = transform(cache)
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: .atomic)
        cache = next
    }
}
