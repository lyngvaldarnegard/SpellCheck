import AppKit
import ApplicationServices
import SpellCheckCore
import SpellCheckEngine

nonisolated(unsafe) private let axPromptKey = "AXTrustedCheckOptionPrompt"

/// Grabs the current selection — or, when nothing is selected, the sentence
/// around the caret — from the frontmost application through the Accessibility
/// API, and types the corrected text back over the same range.
final class AccessibilityTextSource: TextSource, @unchecked Sendable {

    func grab() async throws -> GrabbedText {
        guard AXIsProcessTrustedWithOptions([axPromptKey: true] as CFDictionary) else {
            throw TextSourceError.accessDenied
        }
        let systemWide = AXUIElementCreateSystemWide()
        guard let appElement = copyAttribute(kAXFocusedApplicationAttribute, from: systemWide, as: AXUIElement.self) else {
            throw TextSourceError.noText
        }
        guard let element = copyAttribute(kAXFocusedUIElementAttribute, from: appElement, as: AXUIElement.self) else {
            throw TextSourceError.noText
        }
        guard let document = copyAttribute(kAXValueAttribute, from: element, as: String.self), !document.isEmpty else {
            throw TextSourceError.noText
        }
        guard let rangeValue = copyAttribute(kAXSelectedTextRangeAttribute, from: element, as: AXValue.self),
              let range = cfRange(of: rangeValue) else {
            throw TextSourceError.noText
        }

        nonisolated(unsafe) let capturedElement = element

        if range.length > 0,
           let selected = copyAttribute(kAXSelectedTextAttribute, from: element, as: String.self),
           !selected.isEmpty {
            let location = range.location
            let length = range.length
            return GrabbedText(scope: .selection(selected)) { [weak self] newText in
                await self?.replace(rangeLocation: location, length: length, in: capturedElement, with: newText) ?? false
            }
        }

        let caret = range.location + range.length
        guard let extraction = TextScopeExtractor.sentence(in: document, caretOffset: caret) else {
            throw TextSourceError.noText
        }
        let location = extraction.utf16Location
        let length = extraction.utf16Length
        return GrabbedText(scope: .sentence(extraction.text)) { [weak self] newText in
            await self?.replace(rangeLocation: location, length: length, in: capturedElement, with: newText) ?? false
        }
    }

    /// Selects the given UTF-16 range in the element and pastes `newText` over
    /// it via the clipboard (Cmd-V), which works in any app honoring AX text
    /// selection.
    private func replace(rangeLocation location: Int, length: Int, in element: AXUIElement, with newText: String) async -> Bool {
        var cfRange = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success else {
            return false
        }
        return paste(newText)
    }

    private func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func cfRange(of value: AXValue) -> CFRange? {
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement, as type: T.Type) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
