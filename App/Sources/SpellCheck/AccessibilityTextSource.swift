import AppKit
import ApplicationServices
import SpellCheckCore
import SpellCheckEngine

nonisolated(unsafe) private let axPromptKey = "AXTrustedCheckOptionPrompt"

/// Grabs the current selection — or, when nothing is selected, the sentence
/// around the caret — from the frontmost application through the Accessibility
/// API, and writes the edited text back over the same range.
///
/// Not every editor exposes the same AX attributes, so grabbing works in
/// layers:
///   1. `kAXSelectedTextAttribute` on the focused element (many apps),
///   2. the same attribute on a descendant of the focused element (web areas,
///      Electron/Chromium apps often put the text element deeper in the tree),
///   3. `kAXValueAttribute` + `kAXSelectedTextRangeAttribute` (selection
///      substring, or the sentence around the caret when the selection is
///      empty),
///   4. a clipboard fallback (posts ⌘C, reads the selection, restores the
///      previous clipboard) for editors that expose no usable AX text at all.
///
/// The application the text was grabbed from is captured up front and
/// re-activated before anything is written, so the result never lands in a
/// different app or over a different selection. Replacement is verified via
/// readback whenever the app allows it.
final class AccessibilityTextSource: TextSource, @unchecked Sendable {

    func grab() async throws -> GrabbedText {
        guard AXIsProcessTrustedWithOptions([axPromptKey: false] as CFDictionary) else {
            throw TextSourceError.accessDenied
        }

        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let pid = frontmost?.processIdentifier ?? 0
        let appName = frontmost?.localizedName ?? "the original app"

        let systemWide = AXUIElementCreateSystemWide()
        guard let appElement = copyAttribute(kAXFocusedApplicationAttribute, from: systemWide, as: AXUIElement.self) else {
            throw TextSourceError.noText
        }
        guard let focused = copyAttribute(kAXFocusedUIElementAttribute, from: appElement, as: AXUIElement.self) else {
            throw TextSourceError.noText
        }

        // Layer 1 & 2: an element that reports its selected text directly.
        if let editor = findEditorElement(root: focused, key: kAXSelectedTextAttribute),
           let selected = copyAttribute(kAXSelectedTextAttribute, from: editor, as: String.self),
           !selected.isEmpty {
            let range = selectedTextRange(of: editor)
            nonisolated(unsafe) let capturedEditor = editor
            return GrabbedText(scope: .selection(selected)) { [weak self] newText in
                guard let self else { throw TextSourceError.replaceFailed }
                try await self.replaceViaSelectedText(newText, in: capturedEditor, range: range, pid: pid, appName: appName)
            }
        }

        // Layer 3: full document value + selection range.
        if let editor = findEditorElement(root: focused, key: kAXValueAttribute),
           let document = copyAttribute(kAXValueAttribute, from: editor, as: String.self),
           !document.isEmpty,
           let range = selectedTextRange(of: editor) {
            nonisolated(unsafe) let capturedEditor = editor
            if range.length > 0, let selected = substring(of: document, range: range), !selected.isEmpty {
                return GrabbedText(scope: .selection(selected)) { [weak self] newText in
                    guard let self else { throw TextSourceError.replaceFailed }
                    try await self.replaceViaRange(newText, in: capturedEditor, location: range.location, length: range.length, pid: pid, appName: appName)
                }
            }
            let caret = range.location + range.length
            if let extraction = TextScopeExtractor.sentence(in: document, caretOffset: caret) {
                return GrabbedText(scope: .sentence(extraction.text)) { [weak self] newText in
                    guard let self else { throw TextSourceError.replaceFailed }
                    try await self.replaceViaRange(newText, in: capturedEditor, location: extraction.utf16Location, length: extraction.utf16Length, pid: pid, appName: appName)
                }
            }
        }

        // Layer 4: clipboard fallback — the selection is copied with ⌘C and
        // the replacement is pasted over the (still intact) selection.
        if let copied = try await copySelectionViaClipboard(pid: pid, appName: appName) {
            return GrabbedText(scope: .selection(copied)) { [weak self] newText in
                guard let self else { throw TextSourceError.replaceFailed }
                try await self.replaceViaClipboard(newText, pid: pid, appName: appName)
            }
        }

        throw TextSourceError.noText
    }

    // MARK: Grabbing helpers

    /// Breadth-first search (depth- and size-limited) from `root` for a text
    /// element exposing `key`. Returns `root` itself when it qualifies.
    private func findEditorElement(root: AXUIElement, key: String) -> AXUIElement? {
        if hasAttribute(root, key: key) {
            return root
        }
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        let maxElements = 600
        let maxDepth = 12
        while !queue.isEmpty, visited < maxElements {
            let (element, depth) = queue.removeFirst()
            visited += 1
            guard depth < maxDepth else { continue }
            guard let children = copyAttribute(kAXChildrenAttribute, from: element, as: [AXUIElement].self) else { continue }
            for child in children {
                if hasAttribute(child, key: key) { return child }
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private func hasAttribute(_ element: AXUIElement, key: String) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success, let names else { return false }
        return (names as NSArray).contains(key)
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        guard let rangeValue = copyAttribute(kAXSelectedTextRangeAttribute, from: element, as: AXValue.self) else { return nil }
        return cfRange(of: rangeValue)
    }

    private func substring(of document: String, range: CFRange) -> String? {
        let utf16 = document.utf16
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= utf16.count else { return nil }
        let start = utf16.index(utf16.startIndex, offsetBy: range.location)
        let end = utf16.index(start, offsetBy: range.length)
        return String(decoding: utf16[start..<end], as: UTF16.self)
    }

    /// Last-resort grab: saves the clipboard, clears it, posts ⌘C, reads the
    /// selection and restores the clipboard. Returns nil when nothing was
    /// selected.
    private func copySelectionViaClipboard(pid: pid_t, appName: String) async throws -> String? {
        guard await reactivateTarget(pid: pid, appName: appName) else {
            throw TextSourceError.targetUnavailable(appName)
        }
        let saved = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        postKeyboardShortcut(modifiers: .maskCommand, virtualKey: 0x08 /* C */)
        try await Task.sleep(nanoseconds: 200_000_000)
        let copied = pasteboard.string(forType: .string)
        restorePasteboard(saved)
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    // MARK: Replacement strategies

    /// Replaces by setting the AX selected text directly (optionally after
    /// re-selecting a known range). Works in apps that accept writes to
    /// `kAXSelectedTextAttribute`.
    private func replaceViaSelectedText(_ newText: String, in element: AXUIElement, range: CFRange?, pid: pid_t, appName: String) async throws {
        try await prepareTargetForReplacement(pid: pid, appName: appName)
        if let range {
            var cfRange = range
            if let rangeValue = AXValueCreate(.cfRange, &cfRange) {
                _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            }
        }
        let value: CFTypeRef = newText as NSString
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, value) == .success else {
            throw TextSourceError.replaceFailed
        }
        if let readBack = copyAttribute(kAXSelectedTextAttribute, from: element, as: String.self), readBack != newText {
            throw TextSourceError.replaceFailed
        }
    }

    /// Replaces a UTF-16 range: selects it, then writes the selected text.
    /// Falls back to a clipboard paste when the app does not accept direct
    /// writes.
    private func replaceViaRange(_ newText: String, in element: AXUIElement, location: Int, length: Int, pid: pid_t, appName: String) async throws {
        try await prepareTargetForReplacement(pid: pid, appName: appName)
        var cfRange = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success else {
            throw TextSourceError.replaceFailed
        }
        let value: CFTypeRef = newText as NSString
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, value) == .success {
            if let readBack = copyAttribute(kAXSelectedTextAttribute, from: element, as: String.self), readBack != newText {
                throw TextSourceError.replaceFailed
            }
            return
        }
        // The app ignores direct AX writes — paste over the selected range and
        // verify via readback when possible.
        try await pasteViaClipboard(newText)
        if let document = copyAttribute(kAXValueAttribute, from: element, as: String.self) {
            guard let updated = substring(of: document, range: CFRange(location: location, length: newText.utf16.count)),
                  updated == newText else {
                throw TextSourceError.replaceFailed
            }
        }
        // No readback available: the range was selected and the paste was
        // posted over it.
    }

    /// Replaces the current (unknown) selection by pasting over it.
    private func replaceViaClipboard(_ newText: String, pid: pid_t, appName: String) async throws {
        try await prepareTargetForReplacement(pid: pid, appName: appName)
        try await pasteViaClipboard(newText)
    }

    /// Brings the original application back to the front and waits for it to
    /// actually become frontmost, so the text is never written into a
    /// different app.
    private func prepareTargetForReplacement(pid: pid_t, appName: String) async throws {
        guard await reactivateTarget(pid: pid, appName: appName) else {
            throw TextSourceError.targetUnavailable(appName)
        }
    }

    private func reactivateTarget(pid: pid_t, appName: String) async -> Bool {
        guard pid != 0 else { return false }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        if frontmost == pid { return true }
        _ = await MainActor.run { app.activate() }
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let current = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            if current == pid { return true }
        }
        return false
    }

    /// Saves the clipboard, pastes `text` with ⌘V, then restores the saved
    /// clipboard so the user's clipboard is not clobbered.
    private func pasteViaClipboard(_ text: String) async throws {
        let saved = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextSourceError.replaceFailed
        }
        postKeyboardShortcut(modifiers: .maskCommand, virtualKey: 0x09 /* V */)
        try await Task.sleep(nanoseconds: 200_000_000)
        restorePasteboard(saved)
    }

    private func snapshotPasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
        NSPasteboard.general.pasteboardItems?.compactMap { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
    }

    private func restorePasteboard(_ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        for itemData in saved {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    private func postKeyboardShortcut(modifiers: CGEventFlags, virtualKey: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: AX plumbing

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
