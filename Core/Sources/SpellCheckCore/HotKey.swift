import Foundation

/// Modifier flags stored as CGEventFlags-style bits, so they can be passed
/// straight to CoreGraphics / Carbon on macOS.
public enum ModifierFlags {
    public static let shift: UInt32 = 1 << 17   // CGEventFlags.maskShift
    public static let control: UInt32 = 1 << 18 // CGEventFlags.maskControl
    public static let option: UInt32 = 1 << 19  // CGEventFlags.maskAlternate
    public static let command: UInt32 = 1 << 20 // CGEventFlags.maskCommand
    public static let all: UInt32 = shift | control | option | command
}

/// A global keyboard shortcut: a Carbon virtual key code plus a modifier mask.
public struct HotKey: Codable, Equatable, Sendable {
    /// Carbon virtual key code. `0` means "no key".
    public var keyCode: UInt32
    /// Modifier mask, see `ModifierFlags`.
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// No shortcut configured.
    public static let none = HotKey(keyCode: 0, modifiers: 0)

    /// The default shortcut: Option-L (opens the prompt picker).
    public static let `default` = HotKey(keyCode: 37 /* kVK_ANSI_L */, modifiers: ModifierFlags.option)

    /// The pre-v2 default shortcut (Option-Command-K). Recognized during
    /// settings migration so existing installs move to Option-L.
    public static let legacyDefault = HotKey(keyCode: 40 /* kVK_ANSI_K */, modifiers: ModifierFlags.option | ModifierFlags.command)
}

public extension HotKey {
    var isSet: Bool { keyCode != 0 }

    /// Any shortcut with at least one modifier can be registered globally —
    /// including Option-only combos like the default Option-L. A shortcut
    /// without any modifier would swallow ordinary typing and is rejected.
    /// (Registered Carbon hot keys consume the keystroke, so the character is
    /// not typed into the target app.)
    var isUsableAsGlobalHotkey: Bool {
        isSet && modifiers != 0
    }

    /// Human readable form, e.g. "⌥⌘K".
    var description: String {
        guard isSet else { return "None" }
        var parts: [String] = []
        if modifiers & ModifierFlags.control != 0 { parts.append("⌃") }
        if modifiers & ModifierFlags.option != 0 { parts.append("⌥") }
        if modifiers & ModifierFlags.shift != 0 { parts.append("⇧") }
        if modifiers & ModifierFlags.command != 0 { parts.append("⌘") }
        parts.append(KeyCodeNames.name(for: keyCode) ?? "Key(\(keyCode))")
        return parts.joined()
    }
}

/// Names for the Carbon virtual key codes SpellCheck is likely to encounter.
public enum KeyCodeNames {
    public static func name(for keyCode: UInt32) -> String? {
        switch keyCode {
        case 0: return "A";   case 11: return "B";  case 8: return "C"
        case 2: return "D";   case 14: return "E";  case 3: return "F"
        case 5: return "G";   case 4: return "H";   case 34: return "I"
        case 38: return "J";  case 40: return "K";  case 37: return "L"
        case 46: return "M";  case 45: return "N";  case 31: return "O"
        case 35: return "P";  case 12: return "Q";  case 15: return "R"
        case 1: return "S";   case 17: return "T";  case 32: return "U"
        case 9: return "V";   case 13: return "W";  case 7: return "X"
        case 16: return "Y";  case 6: return "Z"
        case 18: return "1";  case 19: return "2";  case 20: return "3"
        case 21: return "4";  case 23: return "5";  case 22: return "6"
        case 26: return "7";  case 28: return "8";  case 25: return "9"
        case 29: return "0"
        case 27: return "-";  case 24: return "=";  case 30: return "]"
        case 33: return "[";  case 39: return "'";  case 41: return ";"
        case 42: return "\\"; case 43: return ",";  case 47: return "."
        case 44: return "/";  case 50: return "`"
        case 36: return "↩";  case 48: return "⇥";  case 49: return "Space"
        case 51: return "⌫";  case 53: return "esc"
        case 117: return "FwdDel"
        case 115: return "Home"; case 119: return "End"
        case 116: return "PgUp"; case 121: return "PgDn"
        case 123: return "←"; case 124: return "→"
        case 125: return "↓"; case 126: return "↑"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"
        case 118: return "F4"; case 96: return "F5"; case 97: return "F6"
        case 98: return "F7"; case 100: return "F8"; case 101: return "F9"
        case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        case 105: return "F13"; case 107: return "F14"; case 113: return "F15"
        default: return nil
        }
    }
}
