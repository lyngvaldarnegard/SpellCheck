import Foundation
import Testing
@testable import SpellCheckCore

struct HotKeyTests {

    @Test func defaultHotkeyIsOptionCommandK() {
        #expect(HotKey.default.keyCode == 40)
        #expect(HotKey.default.modifiers == ModifierFlags.option | ModifierFlags.command)
        #expect(HotKey.default.isUsableAsGlobalHotkey)
    }

    @Test func noneIsNotSet() {
        #expect(!HotKey.none.isSet)
        #expect(!HotKey.none.isUsableAsGlobalHotkey)
    }

    @Test func globalHotkeyRequiresCommandOrControl() {
        #expect(!HotKey(keyCode: 40, modifiers: ModifierFlags.option).isUsableAsGlobalHotkey)
        #expect(!HotKey(keyCode: 40, modifiers: ModifierFlags.shift).isUsableAsGlobalHotkey)
        #expect(HotKey(keyCode: 40, modifiers: ModifierFlags.command).isUsableAsGlobalHotkey)
        #expect(HotKey(keyCode: 40, modifiers: ModifierFlags.control).isUsableAsGlobalHotkey)
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
        #expect(KeyCodeNames.name(for: 40) == "K")
        #expect(KeyCodeNames.name(for: 49) == "Space")
        #expect(KeyCodeNames.name(for: 9999) == nil)
    }
}
