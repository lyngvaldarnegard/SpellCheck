import Foundation

/// A stable, non-sensitive prompt cache key for providers that support
/// prompt caching (e.g. Mistral's `prompt_cache_key`).
///
/// The key is derived only from the shared prompt and the selected prompt's
/// instruction — the parts of the request that repeat across edits — so
/// identical request prefixes share the same key and cache routing is
/// encouraged. It never contains API keys, user text, prompt contents or
/// anything readable; it is a 64-bit FNV-1a digest rendered as hex.
public enum PromptCacheKey {

    /// Deterministic cache key for one (shared prompt, prompt) pair.
    /// Whitespace-only differences do not change the key.
    public static func make(sharedPrompt: String, prompt: String) -> String {
        let shared = sharedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (shared + "\u{1F}" + instruction).utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(format: "spellcheck-%016llx", hash)
    }
}
