import AppKit

/// Modal confirmation window: shows the original and corrected text and asks
/// the user to accept the replacement before anything is typed back.
@MainActor
final class ConfirmationWindowController: NSObject, NSWindowDelegate {

    private let window: NSPanel
    private var continuation: CheckedContinuation<Bool, Never>?

    init(original: String, corrected: String) {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "SpellCheck — Review"
        window.center()
        window.delegate = self

        let originalView = Self.makeScrollableText(original)
        let correctedView = Self.makeScrollableText(corrected)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(Self.labeled("Original", view: originalView))
        stack.addArrangedSubview(Self.labeled("Corrected", view: correctedView))

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let replaceButton = NSButton(title: "Replace", target: self, action: #selector(accept(_:)))
        replaceButton.keyEquivalent = "\r"

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        let spacer = NSView()
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(replaceButton)
        stack.addArrangedSubview(buttons)

        window.contentView = stack
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            ])
        }
    }

    private static func makeScrollableText(_ text: String) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = text
        textView.drawsBackground = true
        scroll.documentView = textView
        return scroll
    }

    private static func labeled(_ title: String, view: NSView) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.spacing = 4
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        box.addArrangedSubview(label)
        box.addArrangedSubview(view)
        return box
    }

    /// Shows the confirmation window and returns the user's choice.
    static func confirm(original: String, corrected: String) async -> Bool {
        let controller = ConfirmationWindowController(original: original, corrected: corrected)
        return await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func accept(_ sender: Any?) {
        finish(answer: true)
    }

    @objc private func cancel(_ sender: Any?) {
        finish(answer: false)
    }

    func windowWillClose(_ notification: Notification) {
        finish(answer: false)
    }

    private func finish(answer: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        window.orderOut(nil)
        continuation.resume(returning: answer)
    }
}
