import AppKit

/// Modal confirmation window: shows the original and corrected text side by
/// side (or stacked) and asks the user to accept the replacement.
@MainActor
final class ConfirmationWindowController: NSWindowController {

    private let originalView: NSTextView
    private let correctedView: NSTextView
    private var continuation: CheckedContinuation<Bool, Never>?

    init(original: String, corrected: String) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpellCheck — Review"
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        originalView = Self.makeTextView()
        originalView.string = original
        correctedView = Self.makeTextView()
        correctedView.string = corrected

        stack.addArrangedSubview(Self.label("Original", textView: originalView))
        stack.addArrangedSubview(Self.label("Corrected", textView: correctedView))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.keyEquivalent = "\u{1b}"
        let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
        replaceButton.keyEquivalent = "\r"
        replaceButton.keyEquivalentModifierMask = []

        let spacer = NSView()
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(replaceButton)
        stack.addArrangedSubview(buttons)

        window.contentView = stack
        stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16).isActive = true
        stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16).isActive = true
        stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16).isActive = true
        stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16).isActive = true

        self.init(window: window)

        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        replaceButton.target = self
        replaceButton.action = #selector(accept(_:))
    }

    private static func makeTextView() -> NSTextView {
        let scroll = NSScrollView()
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        return textView
    }

    private static func label(_ title: String, textView: NSTextView) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.spacing = 4
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        box.addArrangedSubview(label)
        if let scroll = textView.enclosingScrollView {
            box.addArrangedSubview(scroll)
        }
        return box
    }

    @MainActor
    static func confirm(original: String, corrected: String) async -> Bool {
        let controller = ConfirmationWindowController(original: original, corrected: corrected)
        return await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func accept(_ sender: Any?) {
        finish(answer: true)
    }

    @objc private func cancel(_ sender: Any?) {
        finish(answer: false)
    }

    override func windowWillClose(_ notification: Notification) {
        finish(answer: false)
    }

    private func finish(answer: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        window?.orderOut(nil)
        continuation.resume(returning: answer)
    }
}
