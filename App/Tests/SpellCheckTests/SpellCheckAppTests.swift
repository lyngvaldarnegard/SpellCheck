import Testing
import SpellCheckCore
@testable import SpellCheck

struct AppWiringTests {

    @Test func defaultSettingsAreRuleBasedOffline() {
        #expect(Settings.default.backend == .ruleBased)
        #expect(Settings.default.hotKey == .default)
        #expect(Settings.default.showConfirmation == true)
    }

    @Test func defaultHotKeyIsUsableGlobally() {
        #expect(Settings.default.hotKey.isUsableAsGlobalHotkey)
        #expect(Settings.default.hotKey.description == "⌥⌘K")
    }

    @Test func builtinActionsHaveInstructions() {
        for action in BuiltinAction.allCases {
            #expect(!action.instruction.isEmpty)
        }
    }
}
