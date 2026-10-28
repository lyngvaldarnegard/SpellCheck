import Foundation

/// Persisted user settings. Stored as JSON in the app's Application Support
/// directory; `Codable` keeps the shape versionable.
public struct Settings: Codable, Equatable, Sendable {
    public var hotKey: HotKey
    public var backend: BackendKind
    public var apiKey: String
    public var model: String
    public var baseURL: String
    public var customPrompts: [CustomPrompt]
    public var translationLanguage: String
    public var launchAtLogin: Bool
    public var showConfirmation: Bool

    public init(
        hotKey: HotKey = .default,
        backend: BackendKind = .ruleBased,
        apiKey: String = "",
        model: String = "gpt-4o-mini",
        baseURL: String = "https://api.openai.com/v1",
        customPrompts: [CustomPrompt] = [],
        translationLanguage: String = "German",
        launchAtLogin: Bool = false,
        showConfirmation: Bool = true
    ) {
        self.hotKey = hotKey
        self.backend = backend
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.customPrompts = customPrompts
        self.translationLanguage = translationLanguage
        self.launchAtLogin = launchAtLogin
        self.showConfirmation = showConfirmation
    }

    public static let `default` = Settings()
}

public enum BackendKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case ruleBased = "Offline (rule-based)"
    case openAICompatible = "OpenAI-compatible API"

    public var id: String { rawValue }
}

/// A user-defined custom prompt shown in the SpellCheck menu.
public struct CustomPrompt: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var prompt: String

    public init(id: UUID = UUID(), name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}
