import AppKit
import QuartzCore

/// A circular progress bar (a linear progress bar bent into a ring): a faint
/// full-circle track with a bright arc that fills from the top clockwise
/// over the estimated remaining time. If the request takes longer than the
/// estimate, the arc wraps and fills again, over and over, until the action
/// completes and the indicator disappears. Driven by a repeating Core
/// Animation (no per-frame CPU).
final class CircularProgressView: NSView {

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private static let lineWidth: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for layer in [trackLayer, progressLayer] {
            layer.fillColor = NSColor.clear.cgColor
            layer.lineWidth = Self.lineWidth
            layer.lineCap = .round
            layer.frame = bounds
            layer.bounds = bounds
        }
        trackLayer.strokeColor = NSColor(white: 1, alpha: 0.22).cgColor
        trackLayer.strokeEnd = 1
        progressLayer.strokeColor = NSColor(red: 0.19, green: 0.83, blue: 0.34, alpha: 1).cgColor
        progressLayer.strokeEnd = 0
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(progressLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let inset = Self.lineWidth / 2 + 1
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        // The arc starts at 12 o'clock and runs CLOCKWISE on screen. AppKit
        // layer coordinates have y pointing UP, so a visually clockwise sweep
        // is a DECREASING angle: 90° (top) → 0° (right) → -90° (bottom)
        // → -180° (left) → -270° (back to the top). A rotated plain ellipse
        // starts at the bottom instead — that was the v1.0.0 bug.
        let center = CGPoint(x: circleRect.midX, y: circleRect.midY)
        let radius = min(circleRect.width, circleRect.height) / 2
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: CGFloat.pi / 2,
                    endAngle: -CGFloat.pi * 3 / 2,
                    clockwise: true)
        trackLayer.path = path
        progressLayer.path = path
        for layer in [trackLayer, progressLayer] {
            layer.frame = bounds
            layer.bounds = bounds
        }
    }

    /// Fills the ring over `estimatedSeconds` per revolution; when the
    /// estimate is exceeded the arc keeps wrapping around until `stop()`.
    func start(estimatedSeconds: Double) {
        progressLayer.removeAnimation(forKey: "ringFill")
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = 0
        fill.toValue = 1
        fill.duration = max(0.5, estimatedSeconds)
        fill.repeatCount = .infinity
        progressLayer.add(fill, forKey: "ringFill")
    }

    func stop() {
        progressLayer.removeAnimation(forKey: "ringFill")
    }
}
