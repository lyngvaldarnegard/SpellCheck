import AppKit

/// FixKey-style "working" indicator: a circular progress ring shown near the
/// mouse pointer while the AI request is in flight, so the user gets an
/// immediate visual confirmation that the text was sent — plus a sense of
/// how long is left, based on learned response times.
///
/// The ring fills from the top clockwise over the ESTIMATED response time;
/// when the request outlives the estimate the arc wraps and keeps filling
/// until the correction completes and the indicator disappears. Without an
/// estimate (first requests with a model) one revolution takes 1 second.
///
/// The panel is non-activating, never becomes key, ignores all mouse events
/// (clicks pass through to whatever is underneath) and never steals focus
/// from the user's work.
@MainActor
final class WorkingIndicatorController {

    static let panelSize: CGFloat = 40
    /// Revolution time when no response-time estimate exists yet.
    static let defaultSecondsPerRevolution: Double = 1.0

    private var panel: NSPanel?
    private let ring = CircularProgressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

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
        content.translatesAutoresizingMaskIntoConstraints = false
        ring.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(ring)
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 28),
            ring.heightAnchor.constraint(equalToConstant: 28),
        ])
        panel.contentView = content
        return panel
    }

    /// Shows (or repositions) the ring just above the current mouse location.
    /// `estimatedSeconds` is the learned estimate for this request; nil means
    /// no samples yet, in which case one revolution takes one second.
    /// If the ring is already showing (e.g. the second `.working` event of the
    /// same run), the animation is NOT restarted — only the position is
    /// refreshed.
    func show(estimatedSeconds: Double?) {
        let panel = self.panel ?? buildPanel()
        self.panel = panel
        position(panel)
        if !isShowing {
            ring.start(estimatedSeconds: estimatedSeconds ?? Self.defaultSecondsPerRevolution)
        }
        panel.orderFrontRegardless()
    }

    /// Hides the ring and stops the animation.
    func hide() {
        ring.stop()
        panel?.orderOut(nil)
    }

    var isShowing: Bool { panel?.isVisible ?? false }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var x = mouse.x - Self.panelSize / 2
        var y = mouse.y + 28
        // Keep the whole ring on screen.
        x = min(max(x, visible.minX + 4), visible.maxX - Self.panelSize - 4)
        if y + Self.panelSize > visible.maxY {
            y = mouse.y - Self.panelSize - 8
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
