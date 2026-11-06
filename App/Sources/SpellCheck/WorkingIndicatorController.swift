import AppKit

/// FixKey-style "working" indicator: a small dark rounded spinner shown near
/// the mouse pointer while the AI request is in flight, so the user gets an
/// immediate visual confirmation that the text was sent and is being worked
/// on — even if the menu bar is out of sight.
///
/// The panel is non-activating, never becomes key, ignores all mouse events
/// (clicks pass through to whatever is underneath) and never steals focus from
/// the user's work.
@MainActor
final class WorkingIndicatorController {

    static let panelSize: CGFloat = 40

    private var panel: NSPanel?
    private let indicator = NSProgressIndicator()

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelSize, height: Self.panelSize),
            styleMask: [.borderless, NSWindow.StyleMask(rawValue: 128) /* NSNonactivatingPanelStyleMask */],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.96).cgColor
        content.layer?.cornerRadius = 12

        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isDisplayedWhenStopped = false
        content.addSubview(indicator)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        panel.contentView = content
        return panel
    }

    /// Shows (or repositions) the spinner just above the current mouse
    /// location. Never activates the app and never takes keyboard focus.
    func show() {
        let panel = self.panel ?? buildPanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        indicator.startAnimation(nil)
    }

    /// Hides the spinner and stops the animation.
    func hide() {
        indicator.stopAnimation(nil)
        panel?.orderOut(nil)
    }

    var isShowing: Bool { panel?.isVisible ?? false }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var x = mouse.x - Self.panelSize / 2
        var y = mouse.y + 28
        // Keep the whole indicator on screen.
        x = min(max(x, visible.minX + 4), visible.maxX - Self.panelSize - 4)
        if y + Self.panelSize > visible.maxY {
            y = mouse.y - Self.panelSize - 8
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
