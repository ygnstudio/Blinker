import AppKit

/// Dwell-capable overlay chip panel; lets the controller treat traffic-light
/// and extra-button panels uniformly.
protocol OverlayDwellPanel: AnyObject {
    /// Updates the dwell progress (0...1); the chip activates at 1.
    func setDwellProgress(_ progress: Double)
    /// Resets dwell state after the cursor leaves the chip.
    func resetDwell()
}

/// Traffic-light colors and the dwell indicator shared by the overlay controls.
public enum OverlayChipDrawing {
    /// The vivid fill color of an enlarged traffic dot — the native traffic
    /// light colors at full saturation, used to tint the native glass button.
    public static func vividColor(for button: TrafficButton) -> NSColor {
        switch button {
        case .close:
            NSColor(srgbRed: 1.0, green: 0.37255, blue: 0.34118, alpha: 1.0)
        case .minimize:
            NSColor(srgbRed: 0.99608, green: 0.73725, blue: 0.18039, alpha: 1.0)
        case .zoom:
            NSColor(srgbRed: 0.15686, green: 0.78431, blue: 0.25098, alpha: 1.0)
        }
    }

    /// The dwell progress arc drawn just outside the circle. With Increase
    /// Contrast enabled the arc thickens, keeping it legible.
    static func drawProgressRing(around circleRect: NSRect, progress: Double) {
        guard progress > 0 else { return }
        let ringRect = circleRect.insetBy(dx: -2, dy: -2)
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
            radius: ringRect.width / 2,
            startAngle: 90,
            endAngle: 90 - 360 * progress,
            clockwise: true
        )
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        path.lineWidth = increaseContrast ? 2.5 : 1.5
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
