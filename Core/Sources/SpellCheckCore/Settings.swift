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
    /// Raw value of the chosen menu-bar icon style (see `MenuBarIconStyle` in the app).
    public var menuBarIconStyle: String

    public init(
        hotKey: HotKey = .default,
        backend: BackendKind = .ruleBased,
        apiKey: String = "",
        model: String = "gpt-4o-mini",
        baseURL: String = "https://api.openai.com/v1",
        customPrompts: [CustomPrompt] = [],
        translationLanguage: String = "German",
        launchAtLogin: Bool = false,
        showConfirmation: Bool = true,
        menuBarIconStyle: String = Settings.defaultMenuBarIconStyle
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
        self.menuBarIconStyle = menuBarIconStyle
    }

    /// Custom decoder so settings files written before `menuBarIconStyle`
    /// existed still load (falling back to the default style).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try c.decode(HotKey.self, forKey: .hotKey)
        backend = try c.decode(BackendKind.self, forKey: .backend)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        model = try c.decode(String.self, forKey: .model)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        customPrompts = try c.decode([CustomPrompt].self, forKey: .customPrompts)
        translationLanguage = try c.decode(String.self, forKey: .translationLanguage)
        launchAtLogin = try c.decode(Bool.self, forKey: .launchAtLogin)
        showConfirmation = try c.decode(Bool.self, forKey: .showConfirmation)
        menuBarIconStyle = try c.decodeIfPresent(String.self, forKey: .menuBarIconStyle) ?? Settings.defaultMenuBarIconStyle
    }

    public static let `default` = Settings()
    public static let defaultMenuBarIconStyle = "omega-check"
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
