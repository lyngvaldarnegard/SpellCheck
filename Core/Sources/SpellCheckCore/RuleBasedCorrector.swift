import Foundation

/// A small, fully offline, rule-based corrector used when no LLM backend is
/// configured. It fixes the highest-frequency English typing mistakes: doubled
/// letters, doubled words, missing spaces after sentence punctuation, missing
/// capital at the start of a sentence, and a table of very common misspellings.
public enum RuleBasedCorrector {

    /// Applies all rules and returns the corrected text. Returns `nil` when
    /// nothing changed, so callers can skip replacing text needlessly.
    public static func correct(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        var result = text
        var changed = false

        if let r = fixDoubledLetters(result) { result = r; changed = true }
        if let r = fixDoubledWords(result) { result = r; changed = true }
        if let r = fixMissingSpaceAfterPunctuation(result) { result = r; changed = true }
        if let r = fixCapitalization(result) { result = r; changed = true }
        if let r = fixCommonMisspellings(result) { result = r; changed = true }

        return changed ? result : nil
    }

    // MARK: - Rules

    /// "teh" -> "the", "recieve" -> "receive", "adress" -> "address", ...
    static let commonMisspellings: [String: String] = [
        "teh": "the", "hte": "the", "adn": "and", "nad": "and",
        "recieve": "receive", "recieved": "received", "recieving": "receiving",
        "seperate": "separate", "seperated": "separated",
        "occured": "occurred", "occuring": "occurring",
        "neccessary": "necessary", "necesary": "necessary",
        "accomodate": "accommodate", "accomodation": "accommodation",
        "definately": "definitely", "definatly": "definitely",
        "wierd": "weird", "freind": "friend", "beleive": "believe",
        "beleived": "believed", "calender": "calendar", "collegue": "colleague",
        "comming": "coming", "existance": "existence", "goverment": "government",
        "happend": "happened", "independant": "independent", "maintainance": "maintenance",
        "occurence": "occurrence", "persistant": "persistent", "publically": "publicly",
        "refering": "referring", "relevent": "relevant", "remeber": "remember",
        "sucessful": "successful", "tommorow": "tomorrow", "untill": "until",
        "wich": "which", "withing": "within", "writting": "writing",
        "thier": "their", "tehy": "they", "towrad": "toward",
        "grammer": "grammar", "speling": "spelling", "misake": "mistake",
        "gaurantee": "guarantee", "arguement": "argument",
    ]

    /// Fixes known misspellings, preserving the case of the first letter.
    public static func fixCommonMisspellings(_ text: String) -> String? {
        var result = text
        var changed = false
        for (wrong, right) in commonMisspellings {
            result = replaceWord(result, wrong, with: right) { changed = true }
        }
        return changed ? result : nil
    }

    /// "I beleive so" -> "I believe so" (case-preserving whole-word replace).
    static func replaceWord(_ text: String, _ wrong: String, with right: String, onChange: () -> Void) -> String {
        var result = ""
        var i = text.startIndex
        var changed = false
        while i < text.endIndex {
            if text[i].isLetter, let wordEnd = endOfWord(text, at: i) {
                let word = String(text[i..<wordEnd])
                if word.lowercased() == wrong {
                    result += matchCase(word, replacement: right)
                    changed = true
                    onChange()
                } else {
                    result += word
                }
                i = wordEnd
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        _ = changed
        return result
    }

    /// "recieve" -> "receive" but "Recieve" -> "Receive".
    static func matchCase(_ original: String, replacement: String) -> String {
        guard let first = original.first, first.isUppercase else { return replacement }
        var r = replacement
        if let idx = r.firstIndex(where: { $0.isLetter }) {
            r.replaceSubrange(idx...idx, with: String(r[idx]).uppercased())
        }
        return r
    }

    /// Collapses a tripled+ letter to a doubled one ("sooo" -> "soo") but keeps
    /// legitimate doubles ("book", "coffee", "been").
    public static func fixDoubledLetters(_ text: String) -> String? {
        var result = ""
        var i = text.startIndex
        var changed = false
        let allowed = Set("abcdefghijklmnopqrstuvwxyz".filter { !"aeiou".contains($0) }) // doubles of consonants are usually typos, but keep vowel doubles (too, food)
        while i < text.endIndex {
            let c = text[i]
            if c.isLetter,
               let n1 = text.index(i, offsetBy: 1, limitedBy: text.endIndex),
               let n2 = text.index(i, offsetBy: 2, limitedBy: text.endIndex),
               text[n1] == c, text[n2] == c,
               !allowed.contains(c.lowercased().first!) {
                // three or more in a row -> collapse to two
                result.append(c); result.append(c)
                var j = n2
                while j < text.endIndex, text[j].lowercased() == c.lowercased() {
                    j = text.index(after: j)
                    changed = true
                }
                i = j
            } else {
                result.append(c)
                i = text.index(after: i)
            }
        }
        return changed ? result : nil
    }

    /// "the the" -> "the" (case-insensitive, keeps the first occurrence).
    /// Only collapses duplicates separated by spaces/tabs on the same line —
    /// a newline between the two words means they are not a typing slip.
    public static func fixDoubledWords(_ text: String) -> String? {
        var result = ""
        var i = text.startIndex
        var changed = false
        while i < text.endIndex {
            if text[i].isLetter, let wordEnd = endOfWord(text, at: i) {
                let word = String(text[i..<wordEnd])
                // The gap between the two words must be same-line whitespace
                // only (spaces/tabs). A newline means different sentences.
                var j = wordEnd
                while j < text.endIndex, documentIsSpaceOrTab(text[j]) {
                    j = text.index(after: j)
                }
                if j > wordEnd, j < text.endIndex, text[j].isLetter,
                   let nextEnd = endOfWord(text, at: j),
                   String(text[j..<nextEnd]).lowercased() == word.lowercased() {
                    // drop the second word and the whitespace between
                    result += word
                    changed = true
                    i = nextEnd
                    // skip the whitespace gap we just consumed
                    while i < text.endIndex, documentIsSpaceOrTab(text[i]) {
                        i = text.index(after: i)
                    }
                    // emit exactly one space if more text follows on this line
                    if i < text.endIndex, text[i] != "\n" {
                        result += " "
                    }
                } else {
                    result += word
                    i = wordEnd
                }
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        return changed ? result : nil
    }

    /// "Hello.World" -> "Hello. World" (but leaves "3.14" and "e.g." alone).
    public static func fixMissingSpaceAfterPunctuation(_ text: String) -> String? {
        var result = ""
        var i = text.startIndex
        var changed = false
        while i < text.endIndex {
            let c = text[i]
            result.append(c)
            if c == "." || c == "!" || c == "?" {
                let prev = text.index(before: i)
                let next = text.index(after: i)
                let prevIsDigit = prev > text.startIndex && text[prev].isNumber
                let nextIsDigit = next < text.endIndex && text[next].isNumber
                let isDecimal = c == "." && prevIsDigit && nextIsDigit
                if !isDecimal,
                   next < text.endIndex,
                   text[next].isLetter,
                   !(c == "." && isAbbreviationBefore(text, i)) {
                    result.append(" ")
                    changed = true
                }
            }
            i = text.index(after: i)
        }
        return changed ? result : nil
    }

    /// Capitalizes the first letter of the text and of each sentence.
    public static func fixCapitalization(_ text: String) -> String? {
        var chars = Array(text)
        var changed = false
        var capitalizeNext = true
        var prevWasSentenceEnd = false
        for idx in chars.indices {
            let c = chars[idx]
            if c.isLetter {
                if capitalizeNext, c.isLowercase {
                    chars[idx] = Character(String(c).uppercased())
                    changed = true
                }
                capitalizeNext = false
                prevWasSentenceEnd = false
            } else if c == "." || c == "!" || c == "?" || c == "。" {
                prevWasSentenceEnd = true
            } else if c == "\n" {
                capitalizeNext = true
                prevWasSentenceEnd = false
            } else if c.isWhitespace {
                if prevWasSentenceEnd { capitalizeNext = true }
            } else {
                prevWasSentenceEnd = false
            }
        }
        return changed ? String(chars) : nil
    }

    // MARK: - Helpers

    private static func documentIsSpaceOrTab(_ c: Character) -> Bool {
        c == " " || c == "\t"
    }

    private static func endOfWord(_ text: String, at start: String.Index) -> String.Index? {
        var i = start
        while i < text.endIndex, text[i].isLetter {
            i = text.index(after: i)
        }
        return i > start ? i : nil
    }

    private static func isAbbreviationBefore(_ text: String, _ index: String.Index) -> Bool {
        var j = index
        var word = ""
        while j > text.startIndex {
            let before = text.index(before: j)
            guard text[before].isLetter else { break }
            word.insert(text[before], at: word.startIndex)
            j = before
        }
        return TextScopeExtractor.abbreviationSet.contains(word.lowercased())
    }
}

internal extension TextScopeExtractor {
    static let abbreviationSet: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc",
        "eg", "ie", "fig", "no", "nos", "approx", "dept", "est", "inc", "ltd", "co",
    ]
}
