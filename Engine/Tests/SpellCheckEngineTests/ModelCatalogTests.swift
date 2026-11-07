import Foundation
import Testing
import SpellCheckCore
@testable import SpellCheckEngine

struct APIEndpointTests {

    @Test func chatCompletionsURLAppendsPath() {
        let url = APIEndpoint.chatCompletionsURL("https://api.deepseek.com/v1")
        #expect(url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func chatCompletionsURLHandlesTrailingSlash() {
        let url = APIEndpoint.chatCompletionsURL("https://api.deepseek.com/v1/")
        #expect(url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func chatCompletionsURLKeepsFullEndpoint() {
        let url = APIEndpoint.chatCompletionsURL("https://example.com/v1/chat/completions")
        #expect(url?.absoluteString == "https://example.com/v1/chat/completions")
    }

    @Test func emptyBaseURLFallsBackToDefault() {
        let url = APIEndpoint.chatCompletionsURL("   ")
        #expect(url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test func invalidBaseURLReturnsNil() {
        #expect(APIEndpoint.chatCompletionsURL("not a url ::://").map { _ in true } ?? false == false)
    }

    @Test func modelsURLAppendsModels() {
        #expect(APIEndpoint.modelsURL("https://api.deepseek.com/v1")?.absoluteString == "https://api.deepseek.com/v1/models")
        #expect(APIEndpoint.modelsURL("https://api.deepseek.com")?.absoluteString == "https://api.deepseek.com/models")
    }
}

struct ModelCatalogTests {

    @Test func parsesModelIDsSortedAndDeduplicated() throws {
        let json = """
        {"object":"list","data":[
            {"id":"deepseek-reasoner","object":"model"},
            {"id":"deepseek-chat","object":"model"},
            {"id":"deepseek-chat","object":"model"}
        ]}
        """
        let ids = try ModelCatalog.parseModelIDs(from: Data(json.utf8))
        #expect(ids == ["deepseek-chat", "deepseek-reasoner"])
    }

    @Test func parsesEmptyList() throws {
        let ids = try ModelCatalog.parseModelIDs(from: Data(#"{"object":"list","data":[]}"#.utf8))
        #expect(ids.isEmpty)
    }

    @Test func skipsEmptyIDs() throws {
        let json = #"{"data":[{"id":""},{"id":"gpt-4o-mini"}]}"#
        let ids = try ModelCatalog.parseModelIDs(from: Data(json.utf8))
        #expect(ids == ["gpt-4o-mini"])
    }

    @Test func malformedJSONThrows() {
        #expect(throws: DecodingError.self) {
            _ = try ModelCatalog.parseModelIDs(from: Data("not json".utf8))
        }
    }

    @Test func missingDataFieldThrows() {
        #expect(throws: DecodingError.self) {
            _ = try ModelCatalog.parseModelIDs(from: Data(#"{"object":"list"}"#.utf8))
        }
    }
}

struct ModelCatalogLatestFirstTests {

    @Test func latestModelsComeFirstInFamilyGroups() throws {
        let json = """
        {"object":"list","data":[
            {"id":"mistral-large-latest"},
            {"id":"mistral-small-latest"},
            {"id":"magistral-medium-latest"},
            {"id":"voxtral-small-latest"},
            {"id":"mistral-7b-chat"},
            {"id":"codestral-2508"}
        ]}
        """
        let ids = try ModelCatalog.parseModelIDs(from: Data(json.utf8))
        // "latest" variants first, alphabetical within the group; then the rest.
        #expect(ids == [
            "magistral-medium-latest",
            "mistral-large-latest",
            "mistral-small-latest",
            "voxtral-small-latest",
            "codestral-2508",
            "mistral-7b-chat",
        ])
    }

    @Test func nonLatestListsStayAlphabetical() throws {
        let json = """
        {"object":"list","data":[
            {"id":"b-model"},
            {"id":"a-model"}
        ]}
        """
        let ids = try ModelCatalog.parseModelIDs(from: Data(json.utf8))
        #expect(ids == ["a-model", "b-model"])
    }
}
