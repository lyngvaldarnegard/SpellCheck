import AppKit

/// Menu-bar icon styles the user can pick in Settings. Each style maps to a
/// black-on-transparent template PNG in `Resources/MenuBarIcons/` (generated
/// by `scripts/make-icons.mjs`); macOS inverts it automatically in dark mode.
enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    case omegaCheck = "omega-check"
    case omega = "omega"
    case spellcheck = "spellcheck"
    case checkmark = "checkmark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .omegaCheck: return "Omega + checkmark"
        case .omega: return "Omega only"
        case .spellcheck: return "Spellcheck (classic A)"
        case .checkmark: return "Checkmark only"
        }
    }

    /// Template image used for the status item and the Settings preview.
    /// Falls back to the legacy `MenuBarIconTemplate.png` resource.
    var templateImage: NSImage? {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "png", inDirectory: "MenuBarIcons"),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            return image
        }
        if let path = Bundle.main.path(forResource: "MenuBarIconTemplate", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            return image
        }
        return nil
    }

    static func from(settingsValue: String) -> MenuBarIconStyle {
        MenuBarIconStyle(rawValue: settingsValue) ?? .omegaCheck
    }
}
