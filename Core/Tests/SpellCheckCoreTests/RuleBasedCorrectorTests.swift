import Testing
@testable import SpellCheckCore

struct RuleBasedCorrectorTests {

    @Test func fixesCommonMisspelling() {
        #expect(RuleBasedCorrector.correct("I will recieve it tommorow") == "I will receive it tomorrow")
    }

    @Test func misspellingKeepsCapitalization() {
        #expect(RuleBasedCorrector.correct("Teh quick brown fox") == "The quick brown fox")
    }

    @Test func doesNotTouchCorrectWords() {
        #expect(RuleBasedCorrector.correct("The quick brown fox jumps over the lazy dog") == nil)
    }

    @Test func fixesDoubledWord() {
        #expect(RuleBasedCorrector.correct("I went to to the store") == "I went to the store")
    }

    @Test func doubledWordCaseInsensitive() {
        #expect(RuleBasedCorrector.correct("The the end") == "The end")
    }

    @Test func doesNotRemoveLegitimateRepetitionAcrossNewline() {
        #expect(RuleBasedCorrector.fixDoubledWords("very\nvery good") == nil)
        #expect(RuleBasedCorrector.correct("very\nvery good") == "Very\nVery good")
    }

    @Test func fixesMissingSpaceAfterPeriod() {
        #expect(RuleBasedCorrector.correct("Hello.World") == "Hello. World")
        #expect(RuleBasedCorrector.correct("What?!Really") == "What? ! Really".replacingOccurrences(of: " ! ", with: "! "))
    }

    @Test func keepsDecimalPoint() {
        #expect(RuleBasedCorrector.fixMissingSpaceAfterPunctuation("Pi is 3.14 exactly") == nil)
    }

    @Test func keepsAbbreviationPeriod() {
        #expect(RuleBasedCorrector.fixMissingSpaceAfterPunctuation("See Fig.3 for details") == nil)
    }

    @Test func capitalizesFirstLetter() {
        #expect(RuleBasedCorrector.fixCapitalization("hello world") == "Hello world")
    }

    @Test func capitalizesAfterSentenceEnd() {
        #expect(RuleBasedCorrector.fixCapitalization("one. two. three") == "One. Two. Three")
    }

    @Test func capitalizesAfterNewline() {
        #expect(RuleBasedCorrector.fixCapitalization("line one\nline two") == "Line one\nLine two")
    }

    @Test func collapsesTripledConsonant() {
        #expect(RuleBasedCorrector.fixDoubledLetters("I am soooo happy") == "I am soo happy")
    }

    @Test func keepsLegitimateDoubles() {
        #expect(RuleBasedCorrector.fixDoubledLetters("book coffee been") == nil)
    }

    @Test func emptyInputReturnsNil() {
        #expect(RuleBasedCorrector.correct("") == nil)
    }

    @Test func combinedPipeline() {
        let input = "teh cat sat on on the mat.its broken"
        let output = RuleBasedCorrector.correct(input)
        #expect(output == "The cat sat on the mat. Its broken")
    }

    @Test func matchCasePreservesCapital() {
        #expect(RuleBasedCorrector.matchCase("Recieve", replacement: "receive") == "Receive")
        #expect(RuleBasedCorrector.matchCase("recieve", replacement: "receive") == "receive")
    }
}
