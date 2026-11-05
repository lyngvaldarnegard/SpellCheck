import Foundation
import Testing
@testable import SpellCheckCore

struct HotKeyTests {

    @Test func defaultHotkeyIsOptionL() {
        #expect(HotKey.default.keyCode == 37 /* kVK_ANSI_L */)
        #expect(HotKey.default.modifiers == ModifierFlags.option)
        #expect(HotKey.default.isUsableAsGlobalHotkey)
        #expect(HotKey.default.description == "⌥L")
    }

    @Test func legacyDefaultIsOptionCommandK() {
        #expect(HotKey.legacyDefault.keyCode == 40)
        #expect(HotKey.legacyDefault.modifiers == (ModifierFlags.option | ModifierFlags.command))
        #expect(HotKey.legacyDefault != HotKey.default)
    }

    @Test func noneIsNotSet() {
        #expect(!HotKey.none.isSet)
        #expect(!HotKey.none.isUsableAsGlobalHotkey)
    }

    @Test func optionOnlyShortcutsAreUsableGlobally() {
        #expect(HotKey(keyCode: 37, modifiers: ModifierFlags.option).isUsableAsGlobalHotkey)
        #expect(HotKey(keyCode: 40, modifiers: ModifierFlags.command).isUsableAsGlobalHotkey)
        #expect(HotKey(keyCode: 40, modifiers: ModifierFlags.control).isUsableAsGlobalHotkey)
        #expect(HotKey(keyCode: 40, modifiers: ModifierFlags.option | ModifierFlags.command).isUsableAsGlobalHotkey)
        #expect(!HotKey(keyCode: 40, modifiers: 0).isUsableAsGlobalHotkey)
    }

    @Test func descriptionRendersSymbols() {
        #expect(HotKey(keyCode: 40, modifiers: ModifierFlags.option | ModifierFlags.command).description == "⌥⌘K")
        #expect(HotKey(keyCode: 0, modifiers: 0).description == "None")
    }

    @Test func hotkeyIsCodable() throws {
        let hotkey = HotKey(keyCode: 40, modifiers: ModifierFlags.command | ModifierFlags.shift)
        let data = try JSONEncoder().encode(hotkey)
        let decoded = try JSONDecoder().decode(HotKey.self, from: data)
        #expect(decoded == hotkey)
    }

    @Test func keyCodeNames() {
        #expect(KeyCodeNames.name(for: 37) == "L")
        #expect(KeyCodeNames.name(for: 40) == "K")
        #expect(KeyCodeNames.name(for: 49) == "Space")
        #expect(KeyCodeNames.name(for: 9999) == nil)
    }
}
