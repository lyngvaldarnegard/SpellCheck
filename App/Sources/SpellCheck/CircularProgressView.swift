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
            // Start at 12 o'clock and run clockwise.
            layer.transform = CATransform3DMakeRotation(-CGFloat.pi / 2, 0, 0, 1)
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
        let path = CGPath(ellipseIn: circleRect, transform: nil)
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
