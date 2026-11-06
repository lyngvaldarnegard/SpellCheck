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
public struct Prompt: Codable, Equatable, Hashable, Sendable, Identifiable {
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

    /// Lenient decoding: missing keys fall back instead of failing, so one
    /// older-shaped prompt entry can never break or wipe the list.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? PromptIcon.check.rawValue
    }

    private enum CodingKeys: String, CodingKey { case id, name, prompt, icon }

    public var iconKind: PromptIcon { PromptIcon(rawValue: icon) ?? .check }
}

/// Persisted user settings, stored as JSON in the app's Application Support
/// directory. The custom decoder keeps settings files from older versions
/// loadable (unknown keys are ignored, missing keys fall back to defaults).
public struct Settings: Codable, Equatable, Sendable {
    public var hotKey: HotKey
    public var apiKey: String
    public var model: String
    /// Optional backup model (same provider/credentials) retried once when a
    /// request to the primary model fails for a temporary or compatibility reason.
    public var backupModel: String
    public var baseURL: String
    /// Common instruction included in every request, before the selected
    /// prompt's instruction. Editable in Settings; persisted like the rest.
    public var sharedPrompt: String
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
        backupModel: String = "",
        baseURL: String = APIProvider.openAI.baseURL,
        sharedPrompt: String = Settings.defaultSharedPrompt,
        prompts: [Prompt] = [],
        launchAtLogin: Bool = false,
        menuBarIconStyle: String = Settings.defaultMenuBarIconStyle,
        didSeedDefaultPrompts: Bool = false
    ) {
        self.hotKey = hotKey
        self.apiKey = apiKey
        self.model = model
        self.backupModel = backupModel
        self.baseURL = baseURL
        self.sharedPrompt = sharedPrompt
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
        backupModel = try c.decodeIfPresent(String.self, forKey: .backupModel) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? APIProvider.openAI.baseURL
        // Settings files from versions before the shared prompt existed get
        // the editable default once; later user edits always win.
        sharedPrompt = try c.decodeIfPresent(String.self, forKey: .sharedPrompt) ?? Settings.defaultSharedPrompt
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if let prompts = (try? c.decodeIfPresent([LossyPrompt].self, forKey: .prompts)) ?? nil {
            // Decode lossily: a single malformed or renamed prompt entry must
            // never wipe the user's whole prompt list. Entries that carry no
            // recognizable data at all are dropped.
            self.prompts = prompts.compactMap(\.value).filter { !$0.name.isEmpty || !$0.prompt.isEmpty }
        } else if let legacyPrompts = (try? legacy.decodeIfPresent([LossyLegacyPrompt].self, forKey: .customPrompts)) ?? nil {
            // v1 stored user prompts under "customPrompts" (name + prompt, no icon).
            self.prompts = legacyPrompts.compactMap(\.value).map { Prompt(name: $0.name, prompt: $0.prompt) }
        } else {
            self.prompts = []
        }
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        menuBarIconStyle = try c.decodeIfPresent(String.self, forKey: .menuBarIconStyle) ?? Settings.defaultMenuBarIconStyle
        didSeedDefaultPrompts = try c.decodeIfPresent(Bool.self, forKey: .didSeedDefaultPrompts) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey, apiKey, model, backupModel, baseURL, sharedPrompt, prompts
        case launchAtLogin, menuBarIconStyle, didSeedDefaultPrompts
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case customPrompts
    }

    public static let `default` = Settings()
    public static let defaultMenuBarIconStyle = "omega-check"

    /// Editable default for the shared prompt: asks for only the requested
    /// result, in the original language, without unsolicited formatting.
    public static let defaultSharedPrompt = """
    Follow the instruction exactly. Respond in the text's original language \
    unless the instruction explicitly asks for a translation or another language. \
    Return only the finished text — no explanations, preambles, apologies, \
    or artificial delimiters around it.
    """

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

/// Decodes a `Prompt`, yielding nil for entries that do not decode — one bad
/// entry must not fail (and wipe) the entire list.
private struct LossyPrompt: Decodable {
    let value: Prompt?
    init(from decoder: Decoder) throws {
        self.value = try? Prompt(from: decoder)
    }
}

/// Same lossy wrapper for v1 "customPrompts" entries.
private struct LossyLegacyPrompt: Decodable {
    let value: LegacyPrompt?
    init(from decoder: Decoder) throws {
        self.value = try? LegacyPrompt(from: decoder)
    }
}

/// Shape of the v1 "customPrompts" entries, kept only for decoding old files.
private struct LegacyPrompt: Codable {
    var name: String
    var prompt: String
}

public extension Prompt {
    /// The prompts shipped as editable defaults (the user's saved prompt list,
    /// v1.0.0). Norwegian-language prompt sections were removed at the user's
    /// request; the Allvit and Napoloen prompts were dropped. All translation
    /// prompts sit at the bottom of the list.
    static let defaultPrompts: [Prompt] = [
        Prompt(
            name: "Fix Grammar",
            prompt: "Polish the text by fixing grammar, spelling, punctuation, and capitalization only. Keep the same language, meaning, tone, names, numbers, dates, links, and formatting. Return only the polished text.",
            icon: PromptIcon.check.rawValue
        ),
        Prompt(
            name: "Improve Writing",
            prompt: "Rewrite this into polished writing with better clarity, flow, and readability while preserving the original meaning and language. Keep key facts unchanged and return only the rewritten text.",
            icon: PromptIcon.pen.rawValue
        ),
        Prompt(
            name: "Humanize",
            prompt: "You are a careful human-voice editor. Rewrite the text below as polished, natural-sounding writing that reads like a real person sharing honest observations, not a formal article or an AI summary. Keep the original language, meaning, key facts, names, numbers, dates, links, citations, references, quotations, and technical terms exactly as written, and do not add new information, invent claims, or alter the author’s intended meaning or nuance. Keep the original grammatical tense throughout, so past stays past, present stays present, and future stays future, and do not shift tense for style or flow.\n\nFix all grammar, spelling, punctuation, and capitalization errors. Make the text concise, clear, and precise by removing unnecessary words, repetition, and vague formulations, and improve sentence structure, logical flow, and readability without making the language more complicated than it needs to be. Aim for an average sentence length of 15 to 20 words and generally keep sentences under 25 words, splitting any sentence that becomes hard to follow. Allow longer sentences when accuracy or nuance requires it, and vary sentence length and rhythm so the prose never feels mechanical, mixing short, direct sentences with longer ones that carry a thought through. Clarity and natural flow matter more than strict word counts.\n\nWrite with the tone and rhythm of someone who has real experience with the subject. Replace stiff, generic, or overly polished phrasing with plain, specific wording, and cut filler and stock transitions such as “first of all,” “in conclusion,” “furthermore,” “moreover,” “delve,” and “it’s important to note.” Avoid formulaic structures like the rule of three, neat summarizing conclusions, and balanced “not only... but also” constructions unless they genuinely fit. Use contractions where they sound natural, allow mild informality and a little personality where the context permits, and match the register of the intended audience, whether casual, professional, or academic, without drifting from the tone the original purpose requires.\n\nUse fewer words wherever the meaning stays the same. When two versions say the same thing, pick the shorter one, and replace long or unusual expressions with the plain word a person would actually use. The result should normally be shorter than the original.\n\nFact check the text.\n\nDo NOT use em dashes.\n\nReturn only the revised text, with no explanations, comments, or preamble.",
            icon: PromptIcon.pen.rawValue
        ),
        Prompt(
            name: "Make Shorter",
            prompt: "Make this text shorter and cleaner while preserving meaning, tone, and important details. Keep the original language and return only the shortened text.\n\nKEEP REFERENCES TO SOURCES! NEVER REMOVE REFERENCES TO SOURCES!",
            icon: PromptIcon.lines.rawValue
        ),
        Prompt(
            name: "Summarize",
            prompt: "Summarize this text into a clearly shorter version that preserves the main points and factual details. Keep the original language. Return only the summary.",
            icon: PromptIcon.bolt.rawValue
        ),
        Prompt(
            name: "Explain this",
            prompt: "Explain this text in simple, plain language for a non-expert reader while preserving the meaning and key details. Keep the original language. Return only the explanation.",
            icon: PromptIcon.question.rawValue
        ),
        Prompt(
            name: "Convert to Bullet Points",
            prompt: "Rewrite this as concise bullet points that capture all key ideas and facts. Keep the original language and meaning. Return only the bullet list.",
            icon: PromptIcon.lines.rawValue
        ),
        Prompt(
            name: "Convert to Markdown",
            prompt: "Convert this text into clean, valid Markdown. Use headings and lists only when they improve readability. Preserve meaning and key details. Return only Markdown.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Friendly Tone",
            prompt: "Rewrite this text in a friendly, conversational tone while preserving the original meaning and key details. Keep the original language. Return only the rewritten text.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Decline Request by Email",
            prompt: "Write a polite, concise email that declines the request while keeping a respectful and friendly tone. Base it only on the source message. Return only the email text.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "10 Rewrites",
            prompt: "Provide exactly 10 distinct rewrites, each preserving the original meaning but using different wording and rhythm. Output as a numbered list with one line per option. Return only the alternatives.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "TLDR",
            prompt: "Create a TLDR with up to 7 concise bullet points covering essential facts, then add one single-sentence summary. Do not add facts that are not in the source. Return only the TLDR output.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Synonyms",
            prompt: "List strong single-word synonyms for the given word. Exclude duplicates and the original word. Return only the synonyms as a comma-separated list.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Active Voice",
            prompt: "Rewrite this text in active voice while preserving meaning, key details, and original language. Return only the revised text.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Make Persuasive",
            prompt: "Rewrite this text to be more persuasive and compelling while staying accurate and professional. Do not invent evidence, metrics, or claims. Return only the revised text.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Sales Copy",
            prompt: "Transform this into polished sales copy that highlights benefits and includes a clear call to action. Keep claims factual and grounded in the source text. Return only the sales copy.",
            icon: PromptIcon.sparkle.rawValue
        ),
        Prompt(
            name: "Translate to English",
            prompt: "Translate this text into natural English while preserving meaning, tone, and context. Keep names, numbers, dates, and links accurate. Return only the English translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Pinyin to Chinese",
            prompt: "Convert this Pinyin text into simplified Chinese characters accurately. Preserve intended meaning and avoid traditional characters. Return only the converted text.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Chinese",
            prompt: "Translate this text into simplified Chinese while preserving meaning, tone, and context. Avoid traditional characters. Return only the Chinese translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to German",
            prompt: "Translate this text into natural German while preserving meaning, tone, and context. Return only the German translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Spanish",
            prompt: "Translate this text into natural Spanish while preserving meaning, tone, and context. Return only the Spanish translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to French",
            prompt: "Translate this text into natural French while preserving meaning, tone, and context. Return only the French translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Italian",
            prompt: "Translate this text into natural Italian while preserving meaning, tone, and context. Return only the Italian translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Portuguese",
            prompt: "Translate this text into natural Portuguese while preserving meaning, tone, and context. Return only the Portuguese translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Japanese",
            prompt: "Translate this text into natural Japanese while preserving meaning, tone, and context. Return only the Japanese translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Esperanto",
            prompt: "Translate this text into natural Esperanto while preserving meaning, tone, and context. Keep names, numbers, dates, and links accurate. Return only the Esperanto translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Norwegian (Bokmål)",
            prompt: "Translate this text into natural Norwegian Bokmål while preserving meaning, tone, and context. Keep names, numbers, dates, and links accurate. Return only the Bokmål translation.",
            icon: PromptIcon.translate.rawValue
        ),
        Prompt(
            name: "Translate to Norwegian (Nynorsk)",
            prompt: "Translate this text into natural Norwegian Nynorsk while preserving meaning, tone, and context. Keep names, numbers, dates, and links accurate. Return only the Nynorsk translation.",
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
