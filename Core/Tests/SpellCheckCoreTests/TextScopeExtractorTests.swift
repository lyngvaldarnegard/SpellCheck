import Testing
@testable import SpellCheckCore

struct TextScopeExtractorTests {

    @Test func extractsSentenceAtEndOfDocument() {
        let doc = "Hello world. This is a test."
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: doc.utf16.count)
        #expect(result?.text == "This is a test.")
    }

    @Test func extractsSentenceInMiddle() {
        let doc = "First sentence. Second sentence. Third sentence."
        let caret = doc.utf16.index(doc.utf16.startIndex, offsetBy: 20) // inside "Second"
        let caretOffset = doc.utf16.distance(from: doc.utf16.startIndex, to: caret)
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: caretOffset)
        #expect(result?.text == "Second sentence.")
    }

    @Test func caretInFirstSentence() {
        let doc = "Alpha beta. Gamma delta."
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: 3)
        #expect(result?.text == "Alpha beta.")
    }

    @Test func newlineIsABoundary() {
        let doc = "Line one\nLine two\nLine three"
        let caret = doc.utf16.index(doc.utf16.startIndex, offsetBy: 14)
        let caretOffset = doc.utf16.distance(from: doc.utf16.startIndex, to: caret)
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: caretOffset)
        #expect(result?.text == "Line two")
    }

    @Test func emptyDocumentReturnsNil() {
        #expect(TextScopeExtractor.sentence(in: "", caretOffset: 0) == nil)
        #expect(TextScopeExtractor.sentence(in: "   ", caretOffset: 2) == nil)
    }

    @Test func abbreviationDoesNotEndSentence() {
        let doc = "I saw Mr. Smith yesterday. He was nice."
        let caret = doc.utf16.index(doc.utf16.startIndex, offsetBy: 30) // in "He was nice."
        let caretOffset = doc.utf16.distance(from: doc.utf16.startIndex, to: caret)
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: caretOffset)
        #expect(result?.text == "He was nice.")
    }

    @Test func abbreviationAtCaretStart() {
        let doc = "Dr. Jones left. Then he returned."
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: 2) // inside "Dr."
        #expect(result?.text == "Dr. Jones left.")
    }

    @Test func questionAndExclamationMarksEndSentences() {
        let doc = "Are you sure? Yes! Absolutely."
        let caret = doc.utf16.index(doc.utf16.startIndex, offsetBy: 20) // "Absolutely."
        let caretOffset = doc.utf16.distance(from: doc.utf16.startIndex, to: caret)
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: caretOffset)
        #expect(result?.text == "Absolutely.")
    }

    @Test func decimalPointIsNotABoundary() {
        let doc = "It costs 3.14 dollars total. Ok."
        let caret = doc.utf16.index(doc.utf16.startIndex, offsetBy: 5) // inside "3.14"
        let caretOffset = doc.utf16.distance(from: doc.utf16.startIndex, to: caret)
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: caretOffset)
        #expect(result?.text == "It costs 3.14 dollars total.")
    }

    @Test func utf16LocationAndLengthMatchRange() {
        let doc = "Hello wörld. Second sentence here."
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: doc.utf16.count)!
        let utf16 = doc.utf16
        let expectedStart = utf16.distance(from: utf16.startIndex, to: result.range.lowerBound)
        #expect(result.utf16Location == expectedStart)
        #expect(result.utf16Length == utf16.distance(from: result.range.lowerBound, to: result.range.upperBound))
        #expect(String(utf16[utf16.index(utf16.startIndex, offsetBy: result.utf16Location)..<utf16.index(utf16.startIndex, offsetBy: result.utf16Location + result.utf16Length)]) == result.text)
    }

    @Test func emojiInSentenceCountsAsUtf16() {
        let doc = "Hi 👋 there. Next one."
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: doc.utf16.count)!
        #expect(result.text == "Next one.")
        let utf16 = doc.utf16
        #expect(String(utf16[utf16.index(utf16.startIndex, offsetBy: result.utf16Location)..<utf16.index(utf16.startIndex, offsetBy: result.utf16Location + result.utf16Length)]) == result.text)
    }

    @Test func scopeWrapsSentence() {
        let doc = "One. Two."
        let scope = TextScopeExtractor.scope(document: doc, caretOffset: doc.utf16.count)
        #expect(scope == .sentence("Two."))
    }

    @Test func caretInWhitespaceAfterSentenceBelongsToPreviousSentence() {
        let doc = "First.   Second."
        // caret inside the whitespace gap between the two sentences
        let caretOffset = 7
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: caretOffset)
        #expect(result?.text == "First.")
    }

    @Test func singleSentenceWithoutTerminator() {
        let doc = "just a fragment"
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: 5)
        #expect(result?.text == "just a fragment")
    }

    @Test func caretClampedWhenOutOfRange() {
        let doc = "Hello there."
        let result = TextScopeExtractor.sentence(in: doc, caretOffset: 9999)
        #expect(result?.text == "Hello there.")
        let result2 = TextScopeExtractor.sentence(in: doc, caretOffset: -5)
        #expect(result2?.text == "Hello there.")
    }
}
