import AppKit

/// Dwell-capable overlay chip panel; lets the controller treat traffic-light
/// and extra-button panels uniformly.
protocol OverlayDwellPanel: AnyObject {
    /// Updates the dwell progress (0...1); the chip activates at 1.
    func setDwellProgress(_ progress: Double)
    /// Resets dwell state after the cursor leaves the chip.
    func resetDwell()
}

/// Shared chip-drawing primitives used by both the traffic-light button view
/// and the extra-action button view, so the two chip styles stay identical.
enum OverlayChipDrawing {
    /// The vivid fill color of an enlarged traffic dot — the native traffic
    /// light colors at full saturation, opaque so the native button can
    /// never tint the dot through the glass tray.
    static func vividColor(for button: TrafficButton) -> NSColor {
        switch button {
        case .close:
            NSColor(srgbRed: 1.0, green: 0.37255, blue: 0.34118, alpha: 1.0)
        case .minimize:
            NSColor(srgbRed: 0.99608, green: 0.73725, blue: 0.18039, alpha: 1.0)
        case .zoom:
            NSColor(srgbRed: 0.15686, green: 0.78431, blue: 0.25098, alpha: 1.0)
        }
    }

    /// Pre-macOS 26 fallback for the glass chip: a translucent rounded
    /// backdrop so the chip reads on any wallpaper.
    static func drawBackdropChip(in bounds: NSRect) {
        let chipRect = bounds.insetBy(dx: 1, dy: 1)
        NSColor.windowBackgroundColor.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: chipRect, xRadius: 15, yRadius: 15).fill()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        let border = NSBezierPath(roundedRect: chipRect, xRadius: 15, yRadius: 15)
        border.lineWidth = 1
        border.stroke()
    }

    /// The dwell progress arc drawn just outside the circle.
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
        path.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    /// The solid inner circle: opaque fill with a hairline dark rim, like
    /// the native traffic lights — no translucency, so nothing bleeds
    /// through from the glass tray below.
    static func drawCircle(in circleRect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
        NSColor.black.withAlphaComponent(0.16).setStroke()
        let rim = NSBezierPath(ovalIn: circleRect)
        rim.lineWidth = 1
        rim.stroke()
    }

    /// The inner circle rect for a chip of the given bounds (4 pt inset).
    static func circleRect(in bounds: NSRect) -> NSRect {
        let inset: CGFloat = 4
        let diameter = min(bounds.width, bounds.height) - inset * 2
        return CGRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
    }
}
