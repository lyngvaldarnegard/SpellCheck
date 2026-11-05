import Foundation

/// Icon shown next to a prompt in the picker and the Prompt Editor.
public enum PromptIcon: String, CaseIterable, Sendable, Identifiable {
    case check
    case pen
    case bolt
    case question
    case lines
    case translate
    case sparkle

    public var id: String { rawValue }

    /// A text glyph used to render the icon (kept dependency-free).
    public var glyph: String {
        switch self {
        case .check: return "✓"
        case .pen: return "✎"
        case .bolt: return "⚡"
        case .question: return "?"
        case .lines: return "≡"
        case .translate: return "→"
        case .sparkle: return "✨"
        }
    }

    public var displayName: String {
        switch self {
        case .check: return "Check"
        case .pen: return "Pen"
        case .bolt: return "Bolt"
        case .question: return "Question"
        case .lines: return "Lines"
        case .translate: return "Translate"
        case .sparkle: return "Sparkle"
        }
    }
}

/// A user prompt: title plus the full instruction text sent to the AI.
/// Every prompt — seeded or user-created — is an ordinary editable entry.
public struct Prompt: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var prompt: String
    /// Raw value of a `PromptIcon`.
    public var icon: String

    public init(id: UUID = UUID(), name: String, prompt: String, icon: String = PromptIcon.check.rawValue) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.icon = icon
    }

    public var iconKind: PromptIcon { PromptIcon(rawValue: icon) ?? .check }
}

/// Persisted user settings, stored as JSON in the app's Application Support
/// directory. The custom decoder keeps settings files from older versions
/// loadable (unknown keys are ignored, missing keys fall back to defaults).
public struct Settings: Codable, Equatable, Sendable {
    public var hotKey: HotKey
    public var apiKey: String
    public var model: String
    public var baseURL: String
    public var prompts: [Prompt]
    public var launchAtLogin: Bool
    /// Raw value of the chosen menu-bar icon style (see `MenuBarIconStyle` in the app).
    public var menuBarIconStyle: String
    /// Guards the one-time seeding of the default prompt list, so a user who
    /// deliberately deletes every prompt does not get them re-created.
    public var didSeedDefaultPrompts: Bool

    public init(
        hotKey: HotKey = .default,
        apiKey: String = "",
        model: String = APIProvider.openAI.defaultModel,
        baseURL: String = APIProvider.openAI.baseURL,
        prompts: [Prompt] = [],
        launchAtLogin: Bool = false,
        menuBarIconStyle: String = Settings.defaultMenuBarIconStyle,
        didSeedDefaultPrompts: Bool = false
    ) {
        self.hotKey = hotKey
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.prompts = prompts
        self.launchAtLogin = launchAtLogin
        self.menuBarIconStyle = menuBarIconStyle
        self.didSeedDefaultPrompts = didSeedDefaultPrompts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try c.decodeIfPresent(HotKey.self, forKey: .hotKey) ?? .default
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? APIProvider.openAI.defaultModel
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? APIProvider.openAI.baseURL
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if let prompts = try c.decodeIfPresent([Prompt].self, forKey: .prompts) {
            self.prompts = prompts
        } else if let legacyPrompts = try legacy.decodeIfPresent([LegacyPrompt].self, forKey: .customPrompts) {
            // v1 stored user prompts under "customPrompts" (name + prompt, no icon).
            self.prompts = legacyPrompts.map { Prompt(name: $0.name, prompt: $0.prompt) }
        } else {
            self.prompts = []
        }
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        menuBarIconStyle = try c.decodeIfPresent(String.self, forKey: .menuBarIconStyle) ?? Settings.defaultMenuBarIconStyle
        didSeedDefaultPrompts = try c.decodeIfPresent(Bool.self, forKey: .didSeedDefaultPrompts) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey, apiKey, model, baseURL, prompts
        case launchAtLogin, menuBarIconStyle, didSeedDefaultPrompts
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case customPrompts
    }

    public static let `default` = Settings()
    public static let defaultMenuBarIconStyle = "omega-check"

    /// One-time migration for settings written by earlier versions:
    /// moves the pre-v2 default hot key (⌥⌘K) to the new default (⌥L) and
    /// seeds the editable prompt list once. All other settings are preserved.
    public func migrated() -> Settings {
        var next = self
        // Compare only the modifier bits SpellCheck knows about — recorded
        // shortcuts can carry extra device-dependent flags.
        let knownModifiers = next.hotKey.modifiers & ModifierFlags.all
        if next.hotKey.keyCode == HotKey.legacyDefault.keyCode, knownModifiers == HotKey.legacyDefault.modifiers {
            next.hotKey = .default
        }
        if !next.didSeedDefaultPrompts {
            if next.prompts.isEmpty {
                next.prompts = Prompt.defaultPrompts
            }
            next.didSeedDefaultPrompts = true
        }
        return next
    }
}

/// Shape of the v1 "customPrompts" entries, kept only for decoding old files.
private struct LegacyPrompt: Codable {
    var name: String
    var prompt: String
}

public extension Prompt {
    /// The prompts shipped as editable defaults (from the FixKey archive).
    static let defaultPrompts: [Prompt] = [
        Prompt(
            name: "Fix Grammar",
            prompt: "Polish the text by fixing grammar, spelling, punctuation, and capitalization only. Keep the same language, meaning, tone, names, numbers, dates, links, and formatting. Return only the polished text.\n\nWrite legal terms and law names in full, e.g., «skatteloven» instead of «sktl.» and «jamfør» instead of «jf.». Keep FSFIN abbreviated.",
            icon: PromptIcon.check.rawValue
        ),
        Prompt(
            name: "Improve Writing",
            prompt: "Rewrite this into polished writing with better clarity, flow, and readability while preserving the original meaning and language. Keep key facts unchanged and return only the rewritten text.",
            icon: PromptIcon.pen.rawValue
        ),
        Prompt(
            name: "Make Shorter",
            prompt: "Make this text shorter and cleaner while preserving all key information, the original language and meaning. Return only the shortened text.",
            icon: PromptIcon.lines.rawValue
        ),
        Prompt(
            name: "Summarize",
            prompt: "Summarize this text into a clearly shorter version that captures the main points. Keep the original language. Return only the summary.",
            icon: PromptIcon.bolt.rawValue
        ),
        Prompt(
            name: "Explain this",
            prompt: "Explain this text in simple, plain language for a non-expert. Keep the original language. Return only the explanation.",
            icon: PromptIcon.question.rawValue
        ),
        Prompt(
            name: "Convert to Bullet Points",
            prompt: "Rewrite this as concise bullet points that capture the key information. Keep the original language and meaning. Return only the bullet points.",
            icon: PromptIcon.lines.rawValue
        ),
        Prompt(
            name: "Translate to English",
            prompt: "Translate this text into natural English while preserving meaning, tone, and context. Keep names, numbers, dates, and links accurate. Return only the English translation.",
            icon: PromptIcon.translate.rawValue
        ),
    ]
}

/// OpenAI-compatible API providers SpellCheck can be configured with. Each
/// preset pairs a base URL with a model that provider actually serves, so the
/// two can never disagree (e.g. a Mistral base URL with a DeepSeek model).
public enum APIProvider: String, CaseIterable, Sendable, Identifiable {
    case mistral
    case openAI
    case deepSeek
    case openRouter
    case ollama

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mistral: return "Mistral"
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (local)"
        }
    }

    public var baseURL: String {
        switch self {
        case .mistral: return "https://api.mistral.ai/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .mistral: return "mistral-small-latest"
        case .openAI: return "gpt-4o-mini"
        case .deepSeek: return "deepseek-chat"
        case .openRouter: return "mistralai/mistral-small-latest"
        case .ollama: return "llama3.2"
        }
    }

    /// The provider whose base URL matches, if any — used to keep the model
    /// consistent when the user edits the base URL manually.
    public static func matching(baseURL: String) -> APIProvider? {
        allCases.first { $0.baseURL == baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
