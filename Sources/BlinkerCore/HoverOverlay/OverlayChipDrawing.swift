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

    /// The solid inner circle.
    static func drawCircle(in circleRect: NSRect, color: NSColor) {
        color.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: circleRect).fill()
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
