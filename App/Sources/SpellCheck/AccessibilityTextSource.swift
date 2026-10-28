import AppKit
import ApplicationServices
import SpellCheckCore
import SpellCheckEngine

/// Grabs the current selection — or, when nothing is selected, the sentence
/// around the caret — from the frontmost application through the Accessibility
/// API, and can type the corrected text back over it.
final class AccessibilityTextSource: TextSource, @unchecked Sendable {

    private let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]

    func grab() async throws -> GrabbedText {
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            throw TextSourceError.accessDenied
        }
        let systemWide = AXUIElementCreateSystemWide()
        let focusedApp = try await copyAttribute(kAXFocusedApplicationAttribute, from: systemWide)
        guard let appElement: AXUIElement = focusedApp else {
            throw TextSourceError.noText
        }
        let focusedUI = try await copyAttribute(kAXFocusedUIElementAttribute, from: appElement)
        guard let element: AXUIElement = focusedUI else {
            throw TextSourceError.noText
        }

        if let selectedRangeValue = try? copyAttribute(kAXSelectedTextRangeAttribute, from: element),
           let selectedRange: AXValue = selectedRangeValue,
           let selectedTextValue = try? copyAttribute(kAXSelectedTextAttribute, from: element),
           let selectedText = selectedTextValue as? String,
           !selectedText.isEmpty {
            return GrabbedText(scope: .selection(selectedText)) { newText in
                await self.typeOverSelection(newText, rangeValue: selectedRange)
            }
        }

        guard let fullTextValue = try? copyAttribute(kAXValueAttribute, from: element),
              let document = fullTextValue as? String,
              let caretRangeValue = try? copyAttribute(kAXSelectedTextRangeAttribute, from: element),
              let caretRange: AXValue = caretRangeValue,
              let caretOffset = caretOffset(of: caretRange),
              let extraction = TextScopeExtractor.sentence(in: document, caretOffset: caretOffset) else {
            throw TextSourceError.noText
        }
        return GrabbedText(scope: .sentence(extraction.text)) { newText in
            await self.replaceSentence(newText, in: document, location: extraction.utf16Location, length: extraction.utf16Length, element: element)
        }
    }

    private func caretOffset(of range: AXValue) -> Int? {
        var point = CGPoint.zero
        guard AXValueGetType(range) == .cgPoint else { return nil }
        AXValueGetValue(range, .cgPoint, &point)
        return Int(point.x)
    }

    private func typeOverSelection(_ text: String, rangeValue: AXValue) async -> Bool {
        // Select the exact range again, then paste the replacement via the
        // clipboard so apps with custom text views behave.
        setAttribute(kAXSelectedTextRangeAttribute, value: rangeValue)
        return paste(text)
    }

    private func replaceSentence(
        _ text: String,
        in document: String,
        location: Int,
        length: Int,
        element: AXUIElement
    ) async -> Bool {
        var cfRange = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }
        setAttribute(kAXSelectedTextRangeAttribute, value: rangeValue, element: element)
        return paste(text)
    }

    private func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09 /* V */, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }

    private func setAttribute(_ attribute: String, value: Any, element: AXUIElement? = nil) {
        let target = element ?? AccessibilityTextSource.currentFocusedElement()
        guard let target else { return }
        var value = value
        AXUIElementSetAttributeValue(target, attribute as CFString, &value as CFTypeRef)
    }

    private static func currentFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let app = appRef else { return nil }
        var elementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &elementRef) == .success else {
            return nil
        }
        return elementRef as AXUIElement?
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            var result: AnyObject?
            let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
            if status == .success {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: TextSourceError.noText)
            }
        }
    }
}
