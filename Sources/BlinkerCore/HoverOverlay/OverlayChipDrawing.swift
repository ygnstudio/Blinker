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

    /// The dwell progress arc drawn just outside the circle. With Increase
    /// Contrast enabled the arc thickens, mirroring the bolder rim below.
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

    /// The solid inner circle: opaque fill with a hairline dark rim, like
    /// the native traffic lights — no translucency, so nothing bleeds
    /// through from the glass tray below. With Increase Contrast enabled
    /// the rim strengthens to match the system's bolder button outlines.
    static func drawCircle(in circleRect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.black.withAlphaComponent(increaseContrast ? 0.5 : 0.16).setStroke()
        let rim = NSBezierPath(ovalIn: circleRect)
        rim.lineWidth = 1
        rim.stroke()
    }

    /// Symbol ink for a chip filled with `color`: the native traffic dots
    /// always take a dark glyph, but accent-filled chips (whose fill follows
    /// the user's accent color) need a light glyph on dark fills to stay
    /// readable — graphite, purple or brown accents bury a 55%-black glyph.
    static func symbolInk(onFill color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            return NSColor.black.withAlphaComponent(0.55)
        }
        let luminance = 0.2126 * srgb.redComponent
            + 0.7152 * srgb.greenComponent
            + 0.0722 * srgb.blueComponent
        return luminance < 0.5
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.55)
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
