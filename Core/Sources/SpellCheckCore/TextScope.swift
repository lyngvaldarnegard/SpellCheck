import Foundation

/// The piece of text the user asked SpellCheck to work on.
public enum TextScope: Equatable, Sendable {
    /// Text the user explicitly selected.
    case selection(String)
    /// The sentence containing the caret, extracted from a larger document.
    case sentence(String)
}

public extension TextScope {
    /// The raw text to send to a correction backend.
    var text: String {
        switch self {
        case .selection(let text), .sentence(let text):
            return text
        }
    }
}

/// The sentence extracted from a document, together with its location so the
/// caller can select exactly that range again (for example through the
/// Accessibility API, which works in UTF-16 code units).
public struct SentenceExtraction: Equatable, Sendable {
    /// The sentence text, trimmed of surrounding whitespace.
    public let text: String
    /// Range of the sentence inside the source document.
    public let range: Range<String.Index>
    /// Location of the sentence in UTF-16 code units, relative to the document.
    public let utf16Location: Int
    /// Length of the sentence in UTF-16 code units.
    public let utf16Length: Int

    public init(text: String, range: Range<String.Index>, document: String) {
        self.text = text
        self.range = range
        self.utf16Location = document.utf16.distance(from: document.startIndex, to: range.lowerBound)
        self.utf16Length = document.utf16.distance(from: range.lowerBound, to: range.upperBound)
    }
}

/// Extracts the text to correct from a document and a caret position.
public enum TextScopeExtractor {

    /// Characters that end a sentence.
    private static let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]

    /// Lowercased tokens after which a period does not end a sentence
    /// ("Mr. Smith", "e.g. this").
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc",
        "eg", "ie", "fig", "no", "nos", "approx", "dept", "est", "inc", "ltd", "co",
    ]

    /// Returns the sentence containing `caretOffset` (a UTF-16 code unit
    /// offset, matching what the Accessibility API reports). When no caret is
    /// known, the caret is assumed to be at the end of the document. Newlines
    /// always act as sentence boundaries.
    public static func sentence(in document: String, caretOffset: Int?) -> SentenceExtraction? {
        let utf16Count = document.utf16.count
        guard utf16Count > 0 else { return nil }
        let caret = clamp(caretOffset ?? utf16Count, 0, utf16Count)
        let caretIndex = String.Index(utf16Offset: caret, in: document)

        // Scan left from the caret for the most recent sentence boundary.
        // A boundary only starts a new sentence when non-whitespace text
        // follows it before the caret — otherwise the caret is inside the
        // sentence that the boundary closes.
        var start = document.startIndex
        var i = document.startIndex
        while i < caretIndex {
            let c = document[i]
            if c == "\n" {
                start = document.index(after: i)
                i = start
            } else if terminators.contains(c), isSentenceEnd(document, i) {
                var j = document.index(after: i)
                while j < document.endIndex, document[j].isWhitespace, document[j] != "\n" {
                    j = document.index(after: j)
                }
                if j < caretIndex {
                    // Real text follows before the caret: a new sentence starts.
                    start = j
                    i = j
                } else {
                    // The caret is at or inside the whitespace gap after this
                    // boundary, or on the boundary itself: the boundary closes
                    // the sentence the caret is in. Stop scanning.
                    break
                }
            } else {
                i = document.index(after: i)
            }
        }

        // Scan right from the caret for the next sentence boundary. When the
        // caret is inside a whitespace gap after a boundary, the current
        // sentence has already ended at that boundary, so the scan must start
        // from the caret but stop at the boundary the left scan broke on.
        var end = document.endIndex
        var k = max(caretIndex, start)
        while k < document.endIndex {
            let c = document[k]
            if c == "\n" {
                end = k
                break
            }
            if terminators.contains(c), isSentenceEnd(document, k), k > start {
                end = document.index(after: k)
                break
            }
            k = document.index(after: k)
        }

        // If the left scan broke because the caret is in the whitespace gap
        // after a boundary, the sentence ends at that boundary — not at the
        // next one.
        if start == document.startIndex, caretIndex < document.endIndex {
            var m = document.startIndex
            while m < caretIndex {
                let c = document[m]
                if c == "\n" { break }
                if terminators.contains(c), isSentenceEnd(document, m) {
                    let after = document.index(after: m)
                    var j = after
                    while j < document.endIndex, document[j].isWhitespace, document[j] != "\n" {
                        j = document.index(after: j)
                    }
                    if j >= caretIndex {
                        end = after
                        break
                    }
                }
                m = document.index(after: m)
            }
        }

        // Trim surrounding whitespace and adjust the range accordingly.
        var lower = start
        var upper = end
        while lower < upper, document[lower].isWhitespace {
            lower = document.index(after: lower)
        }
        while upper > lower, document[document.index(before: upper)].isWhitespace {
            upper = document.index(before: upper)
        }
        guard lower < upper else { return nil }
        let text = String(document[lower..<upper])
        return SentenceExtraction(text: text, range: lower..<upper, document: document)
    }

    /// Convenience wrapper returning a `TextScope` for the current sentence.
    public static func scope(document: String, caretOffset: Int?) -> TextScope? {
        guard let extraction = sentence(in: document, caretOffset: caretOffset) else { return nil }
        return .sentence(extraction.text)
    }

    /// A terminator only ends a sentence when it is followed by whitespace, a
    /// newline, or the end of the document — and, for periods, when the word
    /// before it is not a known abbreviation.
    private static func isSentenceEnd(_ document: String, _ index: String.Index) -> Bool {
        let next = document.index(after: index)
        if next == document.endIndex { return true }
        let following = document[next]
        guard following.isWhitespace || following == "\n" else { return false }
        if document[index] == "." {
            let word = wordBefore(document, index)
            if abbreviations.contains(word.lowercased()) { return false }
        }
        return true
    }

    private static func wordBefore(_ document: String, _ index: String.Index) -> String {
        var j = index
        var word = ""
        while j > document.startIndex {
            let before = document.index(before: j)
            guard document[before].isLetter else { break }
            word.insert(document[before], at: word.startIndex)
            j = before
        }
        return word
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }
}
