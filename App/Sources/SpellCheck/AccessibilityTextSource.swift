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

/// Collects a compact, human-readable trace of one grab attempt so the
/// failure alert can say exactly which layer or copy measure produced
/// nothing. Development-phase tooling: when a grab is reported broken, the
/// alert itself carries everything needed to diagnose it — no Console.app
/// step required. Dropped entirely once capture is fully polished.
private final class GrabDiagnostics {
    private(set) var lines: [String] = []
    private let started = Date()

    func add(_ line: String) {
        lines.append(line)
        axLog.info("grab diag: \(line, privacy: .public)")
    }

    /// One compact line for an alert, e.g.
    /// "Notion (pid 417): AX 3.0 s, no selection exposed · ⌘C posted · menu Copy: no item · clipboard unchanged 2.5 s"
    func summary(appName: String, pid: pid_t) -> String {
        (["\(appName) (pid \(pid))"] + lines).joined(separator: " · ")
    }
}

/// Grabs the user's selected text from the frontmost application through the
/// Accessibility API and writes the edited text back over the same selection.
///
/// By explicit user decision (18.11.2026) SpellCheck works on selected text
/// only — the former "sentence around the caret" mode is gone; with nothing
/// selected the app reports "No text found — select some text".
///
/// Editors expose their selection in very different ways, so grabbing works
/// in layers:
///   1. `kAXSelectedTextAttribute` on the focused element (many apps),
///   2. the same attribute on a descendant of the focused element (web areas,
///      Electron/Chromium apps often put the text element deeper in the tree),
///   3. `kAXValueAttribute` + `kAXSelectedTextRangeAttribute` with a
///      non-empty selected range,
///   4. a clipboard fallback for editors that expose no usable AX text at
///      all (Notion, some browser editors). Unconditional and outside the
///      grab deadline: the AX searches above can spend the whole budget
///      walking a large web tree. The copy reaches the target app through
///      several independent pipes, because Electron apps drop or delay
///      synthetic keyboard events unpredictably:
///        - synthetic ⌘C posted at the HID event tap,
///        - an Accessibility press of the app's Edit > Copy menu item
///          (Electron apps keep a native menu bar),
///        - the AX "Copy" action on the focused element,
///        - ⌘C posted directly into the target process (CGEventPostToPid),
///          which does not depend on the global event-routing state.
///      Every measure is logged and reported in the failure diagnostics.
///
/// Replacement is clipboard-based (FixKey-style): the corrected text is placed
/// on the pasteboard and pasted over the still-intact selection with ⌘V, so
/// the edit is a normal undoable operation in the target app. Before pasting,
/// the target app is re-activated and the selection is verified to still be
/// the captured one. The paste is issued AT MOST ONCE — there is no retry and
/// (by explicit user decision) no post-paste read-back: the user sees the
/// result on screen, so verification only added latency and notifications.
/// The corrected text intentionally stays on the clipboard.
final class AccessibilityTextSource: TextSource, @unchecked Sendable {

    /// Per-Accessibility-call timeout (seconds). A slow or hung application
    /// can otherwise stall every AX round-trip for the OS default (up to 30+ s
    /// combined). Large Electron/Chromium documents (Notion) can legitimately
    /// need more than the old 0.75 s per round-trip — their AX trees are built
    /// lazily per call — so this went up; the overall deadline below stays the
    /// hard cap on total grab time.
    private static let axMessagingTimeout: Float = 1.25
    /// Overall budget for the AX layers. Grabbing happens before the picker
    /// opens, so this bounds how long ⌥L can take to show any response.
    /// The clipboard fallback layer runs AFTER this deadline: it is the only
    /// layer that works on Electron/browser selections and must always run.
    private static let grabDeadline: TimeInterval = 3.0

    func grab() async throws -> GrabbedText {
        let started = Date()
        let diag = GrabDiagnostics()
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
            throw TextSourceError.noText("\(appName): Accessibility reports no focused application")
        }
        guard let focused = copyAttribute(kAXFocusedUIElementAttribute, from: appElement, as: AXUIElement.self) else {
            axLog.error("grab failed: no focused element in frontmost app (pid \(pid))")
            throw TextSourceError.noText("\(appName): Accessibility reports no focused element")
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
        diag.add("AX \(String(format: "%.1f", -started.timeIntervalSinceNow)) s: no selected text exposed")

        // Layer 3: selection range inside an exposed document value. Only a
        // NON-EMPTY range counts — with nothing selected there is nothing to
        // work on (caret-sentence mode was removed by user decision).
        if Date() < deadline,
           let editor = findEditorElement(root: focused, key: kAXValueAttribute, deadline: deadline),
           let document = copyAttribute(kAXValueAttribute, from: editor, as: String.self),
           !document.isEmpty,
           let range = selectedTextRange(of: editor),
           range.length > 0,
           let selected = substring(of: document, range: range),
           !selected.isEmpty {
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
        diag.add("AX \(String(format: "%.1f", -started.timeIntervalSinceNow)) s: no selection range")

        // Layer 4: clipboard fallback — the selection is copied with ⌘C and
        // the replacement is pasted over the (still intact) selection.
        // Unconditional and outside the grab deadline: the AX searches above
        // can spend the whole budget walking a large web tree (Notion,
        // Chromium) without finding an editor element, and this layer — the
        // only one that works there — must still get its chance.
        if let copied = try await copySelectionViaClipboard(pid: pid, appName: appName, diag: diag) {
            axLog.info("grab: clipboard fallback layer (pid \(pid))")
            let target = CapturedTarget(pid: pid, appName: appName, element: focused, originalText: copied)
            nonisolated(unsafe) let captured = target
            return GrabbedText(scope: .selection(copied)) { [weak self] newText in
                try await self?.replace(newText, target: captured)
            } refocus: { [weak self] in
                await self?.reactivate(pid: pid, appName: appName)
            }
        }

        throw TextSourceError.noText(diag.summary(appName: appName, pid: pid))
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

    /// Last-resort grab: saves the clipboard, clears it, asks the target app
    /// to copy its selection through several independent pipes, reads the
    /// selection and restores the clipboard. Returns nil when nothing landed.
    ///
    /// v1.1.11 (issue #19, Notion): one synthetic ⌘C through the HID tap is
    /// not enough — Electron apps can service the copy late or drop the
    /// keystroke entirely. The copy now reaches the app through four
    /// independent channels, staggered over a ~2.5 s window, and every
    /// channel's outcome is recorded in `diag` so a failure report is
    /// self-explanatory:
    ///   t=0      ⌘C posted at the global HID tap (as before),
    ///   t≈600 ms Edit > Copy menu item pressed via Accessibility,
    ///   t≈600 ms AX "Copy" action on the focused element,
    ///   t≈1 s    ⌘C posted directly into the target process (PostToPid),
    ///   t≈1.6 s  global ⌘C and PostToPid re-posted once more.
    private func copySelectionViaClipboard(pid: pid_t, appName: String, diag: GrabDiagnostics) async throws -> String? {
        guard await reactivate(pid: pid, appName: appName) else {
            throw TextSourceError.targetUnavailable(appName)
        }
        let saved = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let clearedCount = pasteboard.changeCount
        var copied: String?

        let hidPosted = postKeyboardShortcut(modifiers: .maskCommand, virtualKey: 0x08 /* C */)
        diag.add(hidPosted ? "⌘C posted" : "⌘C: post failed")

        for tick in 0..<50 { // up to ~2.5 s for the target app to service the copy
            try await Task.sleep(nanoseconds: 50_000_000)
            if pasteboard.changeCount != clearedCount {
                copied = pasteboard.string(forType: .string)
                if let copied, !copied.isEmpty { break }
            }
            if tick == 12, pasteboard.changeCount == clearedCount {
                let menu = pressCopyMenuItem(pid: pid)
                diag.add(menu ? "menu Edit>Copy pressed" : "menu Edit>Copy: no usable item")
                let axCopy = postCopyAction()
                diag.add(axCopy ? "AX copy action sent" : "AX copy action: not supported")
            }
            if tick == 20, pasteboard.changeCount == clearedCount {
                let toPid = postKeyboardShortcutToPid(pid: pid, modifiers: .maskCommand, virtualKey: 0x08 /* C */)
                diag.add(toPid ? "⌘C posted into process" : "⌘C into process: post failed")
            }
            if tick == 32, pasteboard.changeCount == clearedCount {
                _ = postKeyboardShortcut(modifiers: .maskCommand, virtualKey: 0x08 /* C */)
                _ = postKeyboardShortcutToPid(pid: pid, modifiers: .maskCommand, virtualKey: 0x08 /* C */)
                diag.add("⌘C re-posted")
            }
        }
        axLog.info("clipboard fallback: finished (copied=\(copied?.isEmpty == false))")
        restorePasteboard(saved)
        guard let copied, !copied.isEmpty else {
            diag.add("clipboard unchanged after 2.5 s")
            return nil
        }
        return copied
    }

    /// Presses the target app's Edit > Copy menu item via Accessibility.
    /// Electron apps (Notion) keep a native menu bar even when the web view
    /// ignores synthetic keyboard events — AXPress on the real menu item
    /// performs the same action ⌘C would. Titles are matched
    /// case-insensitively (English menu names); returns false when no Copy
    /// item is found.
    @discardableResult
    private func pressCopyMenuItem(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        bounded(app)
        guard let menuBar = copyAttribute(kAXMenuBarAttribute, from: app, as: AXUIElement.self) else { return false }
        guard let menus = copyAttribute(kAXChildrenAttribute, from: menuBar, as: [AXUIElement].self) else { return false }
        for menu in menus {
            guard let title = copyAttribute(kAXTitleAttribute, from: menu, as: String.self),
                  title.lowercased() == "edit" else { continue }
            guard let items = copyAttribute(kAXChildrenAttribute, from: menu, as: [AXUIElement].self) else { continue }
            for item in items {
                guard let itemTitle = copyAttribute(kAXTitleAttribute, from: item, as: String.self),
                      itemTitle.lowercased() == "copy" else { continue }
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    /// Sends the AX "Copy" action to the currently focused element. Native
    /// AppKit text views implement it; for Electron web areas it depends on
    /// the Chromium AX build. A best-effort complement to the menu press.
    @discardableResult
    private func postCopyAction() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        guard let appElement = copyAttribute(kAXFocusedApplicationAttribute, from: systemWide, as: AXUIElement.self),
              let focused = copyAttribute(kAXFocusedUIElementAttribute, from: appElement, as: AXUIElement.self) else {
            return false
        }
        bounded(focused)
        return AXUIElementPerformAction(focused, kAXCopyAction as CFString) == .success
    }

    // MARK: Replacement

    /// Replaces the captured selection with `newText`:
    ///   1. re-activates the original app,
    ///   2. verifies the captured selection is still intact — aborts otherwise,
    ///   3. pastes ONCE over the selection.
    /// No post-paste verification and no extra waits: the user sees the result
    /// on screen (explicit decision — the read-back only added latency and
    /// notifications he did not want). The pre-paste checks remain, because
    /// they prevent writing into the wrong place.
    private func replace(_ newText: String, target: CapturedTarget) async throws {
        nonisolated(unsafe) let target = target
        guard await reactivate(pid: target.pid, appName: target.appName) else {
            throw TextSourceError.targetUnavailable(target.appName)
        }
        try await ensureSelectionIntact(target)
        try await pasteOnce(newText, appName: target.appName)
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

    /// Posts ⌘C directly into the target process. Unlike the global HID tap,
    /// this does not depend on frontmost routing or on the target app's
    /// handling of events it receives through the system event stream — the
    /// events are enqueued straight into the process.
    @discardableResult
    private func postKeyboardShortcutToPid(pid: pid_t, modifiers: CGEventFlags, virtualKey: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        CGEventPostToPid(pid, keyDown)
        CGEventPostToPid(pid, keyUp)
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
