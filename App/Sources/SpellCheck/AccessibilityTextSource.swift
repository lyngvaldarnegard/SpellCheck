import AppKit
import ApplicationServices
import os
import SpellCheckCore
import SpellCheckEngine

nonisolated(unsafe) private let axPromptKey = "AXTrustedCheckOptionPrompt"

/// Non-sensitive diagnostics only: which capture layer ran, how long the grab
/// took, and the replacement outcome. Never logs API keys, prompts, selected
/// text or API responses.
private let axLog = Logger(subsystem: "SpellCheck", category: "ax")

/// Everything captured about the edit target before any focus change: the
/// app (pid + name), the AX text element, the exact original text and —
/// when the app exposes it — the selection range in the document.
private struct CapturedTarget {
    let pid: pid_t
    let appName: String
    let element: AXUIElement
    let originalText: String
    /// UTF-16 range of the grabbed text inside the element's full AXValue,
    /// when the grab came from the document value layer.
    var documentRange: CFRange?
    /// The element's full AXValue at grab time, when readable. If it changed
    /// by replacement time the document was edited in the meantime and the
    /// replacement is a stale operation that must not be pasted.
    var documentValue: String?
}

/// Grabs the current selection — or, when nothing is selected, the sentence
/// around the caret — from the frontmost application through the Accessibility
/// API, and writes the edited text back over the same selection.
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
/// Replacement is clipboard-based (FixKey-style): the corrected text is placed
/// on the pasteboard and pasted over the still-intact selection with ⌘V, so
/// the edit is a normal undoable operation in the target app. Before pasting,
/// the target app is re-activated and the selection is verified to still be
/// the captured one; after pasting, the document is read back when possible.
/// The paste is issued AT MOST ONCE — a failed verification never triggers a
/// second replacement, because the first one may already have changed the
/// document. The corrected text intentionally stays on the clipboard.
final class AccessibilityTextSource: TextSource, @unchecked Sendable {

    /// Per-Accessibility-call timeout (seconds). A slow or hung application
    /// can otherwise stall every AX round-trip for the OS default (up to 30+ s
    /// combined), which made the picker appear to "do nothing" after ⌥L.
    private static let axMessagingTimeout: Float = 0.75
    /// Overall budget for one grab. Grabbing happens before the picker opens,
    /// so this bounds how long ⌥L can take to show any response.
    private static let grabDeadline: TimeInterval = 3.0

    func grab() async throws -> GrabbedText {
        let started = Date()
        defer { axLog.info("grab finished after \(Int(-started.timeIntervalSinceNow * 1000)) ms") }
        guard AXIsProcessTrustedWithOptions([axPromptKey: false] as CFDictionary) else {
            axLog.error("grab failed: accessibility not trusted")
            throw TextSourceError.accessDenied
        }

        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let pid = frontmost?.processIdentifier ?? 0
        let appName = frontmost?.localizedName ?? "the original app"
        let deadline = Date().addingTimeInterval(Self.grabDeadline)

        let systemWide = AXUIElementCreateSystemWide()
        guard let appElement = copyAttribute(kAXFocusedApplicationAttribute, from: systemWide, as: AXUIElement.self) else {
            axLog.error("grab failed: no focused application (pid \(pid))")
            throw TextSourceError.noText
        }
        guard let focused = copyAttribute(kAXFocusedUIElementAttribute, from: appElement, as: AXUIElement.self) else {
            axLog.error("grab failed: no focused element in frontmost app (pid \(pid))")
            throw TextSourceError.noText
        }

        // Layer 1 & 2: an element that reports its selected text directly.
        if let editor = findEditorElement(root: focused, key: kAXSelectedTextAttribute, deadline: deadline),
           let selected = copyAttribute(kAXSelectedTextAttribute, from: editor, as: String.self),
           !selected.isEmpty {
            axLog.info("grab: selected-text layer (pid \(pid))")
            var target = CapturedTarget(
                pid: pid,
                appName: appName,
                element: editor,
                originalText: selected,
                documentRange: nil
            )
            target.documentRange = selectedTextRange(of: editor)
            target.documentValue = copyAttribute(kAXValueAttribute, from: editor, as: String.self)
            nonisolated(unsafe) let captured = target
            return GrabbedText(scope: .selection(selected)) { [weak self] newText in
                try await self?.replace(newText, target: captured)
            } refocus: { [weak self] in
                await self?.reactivate(pid: pid, appName: appName)
            }
        }

        // Layer 3: full document value + selection range.
        if Date() < deadline,
           let editor = findEditorElement(root: focused, key: kAXValueAttribute, deadline: deadline),
           let document = copyAttribute(kAXValueAttribute, from: editor, as: String.self),
           !document.isEmpty,
           let range = selectedTextRange(of: editor) {
            if range.length > 0, let selected = substring(of: document, range: range), !selected.isEmpty {
                axLog.info("grab: document-range layer (pid \(pid))")
                var target = CapturedTarget(pid: pid, appName: appName, element: editor, originalText: selected)
                target.documentRange = range
                target.documentValue = document
                nonisolated(unsafe) let captured = target
                return GrabbedText(scope: .selection(selected)) { [weak self] newText in
                    try await self?.replace(newText, target: captured)
                } refocus: { [weak self] in
                    await self?.reactivate(pid: pid, appName: appName)
                }
            }
            let caret = range.location + range.length
            if let extraction = TextScopeExtractor.sentence(in: document, caretOffset: caret) {
                axLog.info("grab: caret-sentence layer (pid \(pid))")
                var target = CapturedTarget(pid: pid, appName: appName, element: editor, originalText: extraction.text)
                target.documentRange = CFRange(location: extraction.utf16Location, length: extraction.utf16Length)
                target.documentValue = document
                nonisolated(unsafe) let captured = target
                return GrabbedText(scope: .sentence(extraction.text)) { [weak self] newText in
                    try await self?.replace(newText, target: captured)
                } refocus: { [weak self] in
                    await self?.reactivate(pid: pid, appName: appName)
                }
            }
        }

        // Layer 4: clipboard fallback — the selection is copied with ⌘C and
        // the replacement is pasted over the (still intact) selection.
        if Date() < deadline, let copied = try await copySelectionViaClipboard(pid: pid, appName: appName) {
            axLog.info("grab: clipboard fallback layer (pid \(pid))")
            let target = CapturedTarget(pid: pid, appName: appName, element: focused, originalText: copied)
            nonisolated(unsafe) let captured = target
            return GrabbedText(scope: .selection(copied)) { [weak self] newText in
                try await self?.replace(newText, target: captured)
            } refocus: { [weak self] in
                await self?.reactivate(pid: pid, appName: appName)
            }
        }

        throw TextSourceError.noText
    }

    // MARK: Grabbing helpers

    /// Breadth-first search (depth-, size- and deadline-limited) from `root`
    /// for a text element exposing `key`. Returns `root` itself when it
    /// qualifies. The deadline bounds the total time spent walking large AX
    /// trees (e.g. Electron/web apps), so opening the picker cannot stall.
    private func findEditorElement(root: AXUIElement, key: String, deadline: Date) -> AXUIElement? {
        if hasAttribute(root, key: key) {
            return root
        }
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        let maxElements = 600
        let maxDepth = 12
        while !queue.isEmpty, visited < maxElements {
            guard Date() < deadline else { return nil }
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
        bounded(element)
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success, let names else { return false }
        return (names as NSArray).contains(key)
    }

    /// Applies the per-call messaging timeout to an element so a slow or
    /// hung application cannot stall an Accessibility round-trip.
    private func bounded(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
    }

    private static func sameRange(_ a: CFRange, _ b: CFRange) -> Bool {
        a.location == b.location && a.length == b.length
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
        guard await reactivate(pid: pid, appName: appName) else {
            throw TextSourceError.targetUnavailable(appName)
        }
        let saved = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        postKeyboardShortcut(modifiers: .maskCommand, virtualKey: 0x08 /* C */)
        try await Task.sleep(nanoseconds: 250_000_000)
        let copied = pasteboard.string(forType: .string)
        restorePasteboard(saved)
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    // MARK: Replacement

    /// Replaces the captured selection with `newText`:
    ///   1. re-activates the original app,
    ///   2. verifies the captured selection is still intact (re-selecting the
    ///      captured range when the app allows it) — aborts otherwise,
    ///   3. pastes ONCE over the selection,
    ///   4. verifies the document readback when the app exposes AXValue.
    private func replace(_ newText: String, target: CapturedTarget) async throws {
        nonisolated(unsafe) let target = target
        guard await reactivate(pid: target.pid, appName: target.appName) else {
            throw TextSourceError.targetUnavailable(target.appName)
        }
        try await ensureSelectionIntact(target)
        let documentBefore = copyAttribute(kAXValueAttribute, from: target.element, as: String.self)
        try await pasteOnce(newText, appName: target.appName)
        try await verify(target, newText: newText, documentBefore: documentBefore)
    }

    /// Confirms the target's selection is still the captured text before
    /// anything is written. When the app exposes the selection range but not
    /// the selected text, the captured range is re-selected; when neither is
    /// readable, the currently focused element must still be the captured one.
    private func ensureSelectionIntact(_ target: CapturedTarget) async throws {
        nonisolated(unsafe) let target = target
        let element = target.element

        // Stale-operation guard: when the document's value was readable at
        // grab time, it must still be identical now. If the user edited the
        // document (or the app changed it) while the request was in flight,
        // the captured selection no longer refers to the same text — pasting
        // could modify the wrong location, so nothing is written.
        if let capturedValue = target.documentValue,
           let currentValue = copyAttribute(kAXValueAttribute, from: element, as: String.self),
           currentValue != capturedValue {
            axLog.error("replace aborted: document changed since grab")
            throw TextSourceError.selectionChanged(target.appName)
        }

        if let current = copyAttribute(kAXSelectedTextAttribute, from: element, as: String.self) {
            if current == target.originalText { return }
            if let range = target.documentRange, reselect(range, in: element),
               let reread = copyAttribute(kAXSelectedTextAttribute, from: element, as: String.self),
               reread == target.originalText {
                return
            }
            throw TextSourceError.selectionChanged(target.appName)
        }

        if let range = target.documentRange {
            // The app hides the selected text but exposes the range: the range
            // must be unchanged, or re-selectable to the captured one.
            if let currentRange = selectedTextRange(of: element), Self.sameRange(currentRange, range) {
                return
            }
            if reselect(range, in: element),
               let reread = copyAttribute(kAXSelectedTextAttribute, from: element, as: String.self),
               reread == target.originalText {
                return
            }
            if reselect(range, in: element), selectedTextRange(of: element).map({ Self.sameRange($0, range) }) == true {
                return
            }
            throw TextSourceError.selectionChanged(target.appName)
        }

        // No selection info at all (e.g. Electron web areas): only paste when
        // the app is still focused on the captured element.
        let systemWide = AXUIElementCreateSystemWide()
        if let focusedApp = copyAttribute(kAXFocusedApplicationAttribute, from: systemWide, as: AXUIElement.self),
           let focused = copyAttribute(kAXFocusedUIElementAttribute, from: focusedApp, as: AXUIElement.self),
           CFEqual(focused, element) {
            return
        }
        throw TextSourceError.selectionChanged(target.appName)
    }

    @discardableResult
    private func reselect(_ range: CFRange, in element: AXUIElement) -> Bool {
        var cfRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success
    }

    /// Places `text` on the clipboard and posts ⌘V exactly once. The user's
    /// previous clipboard is restored only when the paste could not be issued
    /// at all; once the keystroke is posted the corrected text intentionally
    /// stays on the clipboard.
    private func pasteOnce(_ text: String, appName: String) async throws {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard()
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(saved)
            throw TextSourceError.replaceFailed
        }
        guard postKeyboardShortcut(modifiers: .maskCommand, virtualKey: 0x09 /* V */) else {
            restorePasteboard(saved)
            throw TextSourceError.replaceFailed
        }
        // The keystroke was sent — never restore the old clipboard now, the
        // corrected text is the useful thing to keep.
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    /// Reads the document back after the paste. A matching document confirms
    /// success; an unchanged document means nothing happened; anything else
    /// is reported as an unverified (possibly partial) change. Never retries.
    private func verify(_ target: CapturedTarget, newText: String, documentBefore: String?) async throws {
        nonisolated(unsafe) let target = target
        guard let before = documentBefore else {
            // No document readback available — do not claim success.
            throw TextSourceError.unverified(target.appName)
        }
        var after = before
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 150_000_000)
            if let value = copyAttribute(kAXValueAttribute, from: target.element, as: String.self) {
                after = value
                if after != before { break }
            } else {
                throw TextSourceError.unverified(target.appName)
            }
        }
        if after == before {
            // The paste did not land anywhere: nothing was changed.
            throw TextSourceError.replaceFailed
        }
        if expectedDocument(before, original: target.originalText, newText: newText, range: target.documentRange) == after {
            return
        }
        if after.contains(newText) {
            return
        }
        throw TextSourceError.unverified(target.appName)
    }

    /// The document value expected after a successful replacement.
    private func expectedDocument(_ before: String, original: String, newText: String, range: CFRange?) -> String? {
        let utf16 = before.utf16
        if let range, range.location >= 0, range.location + range.length <= utf16.count {
            let start = utf16.index(utf16.startIndex, offsetBy: range.location)
            let end = utf16.index(start, offsetBy: range.length)
            var result = String(decoding: utf16[utf16.startIndex..<start], as: UTF16.self)
            result += newText
            result += String(decoding: utf16[end...], as: UTF16.self)
            return result
        }
        if let lower = before.range(of: original) {
            return before.replacingCharacters(in: lower, with: newText)
        }
        return nil
    }

    /// Brings the original application back to the front and waits for it to
    /// actually become frontmost, so the text is never written into a
    /// different app.
    private func reactivate(pid: pid_t, appName: String) async -> Bool {
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

    @discardableResult
    private func postKeyboardShortcut(modifiers: CGEventFlags, virtualKey: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: AX plumbing

    private func cfRange(of value: AXValue) -> CFRange? {
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement, as type: T.Type) -> T? {
        bounded(element)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
