import AppKit

/// Click-through glass capsule tray sitting behind the enlarged chips while
/// the overlay is visible.
///
/// The tray is the single "base" of the whole hover group: a system Liquid
/// Glass pill (neutral `underWindowBackground` material before macOS 26)
/// spanning the enlarged traffic lights and the extra chips, plus a bounded
/// radial glow behind each traffic dot. The glass is composited live by the
/// system, so the tray adapts to any title-bar content with no sampling and
/// no Screen Recording permission.
///
/// The glow exists because the glass smears the native traffic buttons into
/// soft color ghosts that the enlarged dots cannot fully cover; each glow
/// fades from the dot's edge to zero within `0.32 × dot` width, so it always
/// stays inside the tray margins and can never be clipped by the panel frame.
/// It sits one window level below the chip panels and ignores mouse events,
/// so clicks fall through to the enlarged chips above.
final class HoverOverlayTrayPanel: OverlayPanel {
    /// Horizontal tray margin around the displayed chips' bounding box (pt).
    static let horizontalMargin: CGFloat = 16
    /// Vertical tray margin around the displayed chips' bounding box (pt).
    static let verticalMargin: CGFloat = 12

    /// One traffic dot's glow descriptor.
    struct Glow {
        /// The dot's circle rect in tray-local (AppKit, bottom-left origin)
        /// coordinates.
        let rect: CGRect
        /// The dot's vivid fill color.
        let color: NSColor
    }

    /// - Parameters:
    ///   - trayFrame: The capsule frame, in AX (top-left origin) global
    ///     coordinates — the displayed chips' bounding box inflated by the
    ///     tray margins.
    ///   - glows: The per-dot glows drawn on the glass, in tray-local
    ///     coordinates.
    init(trayFrame: CGRect, glows: [Glow]) {
        let appKitFrame = AXQuery.appKitFrame(fromAXRect: trayFrame)
        // One level below the enlarged chips: the tray must never cover
        // them, no matter the fronting order, while staying above regular
        // app windows.
        super.init(
            appKitFrame: appKitFrame,
            level: NSWindow.Level(NSWindow.Level.popUpMenu.rawValue - 1),
            ignoresMouseEvents: true
        )
        acceptsMouseMovedEvents = false

        let size = appKitFrame.size
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        // Pill shape: the corner radius is derived from the frame height.
        // The subviews track the container so a reused tray can simply be
        // resized (see `update`) instead of torn down and rebuilt. The
        // glow view goes into the glass's contentView — that's what makes
        // the material actually attach (a sibling subview degrades to
        // static frost).
        let glass = GlassBackdrop.makeView(
            size: size,
            cornerRadius: size.height / 2,
            autoresizingMask: [.width, .height]
        )
        let glowView = TrayGlowView(frame: NSRect(origin: .zero, size: size))
        glowView.autoresizingMask = [.width, .height]
        glowView.glows = glows
        GlassBackdrop.host(glowView, in: glass)
        container.addSubview(glass)
        contentView = container
    }

    /// Re-points a kept-alive tray at a new layout: moves the window to the
    /// new capsule frame and redraws the glows. The glass blend belongs to
    /// the (still-existing) window, so re-showing a reused tray never
    /// re-flashes the unblended base color the way a freshly created panel
    /// does.
    func update(trayFrame: CGRect, glows: [Glow]) {
        setFrame(AXQuery.appKitFrame(fromAXRect: trayFrame), display: true)
        guard
            let container = contentView as? NSView,
            let glowView = container.subviews.compactMap({ $0 as? TrayGlowView }).first
        else { return }
        glowView.glows = glows
        glowView.needsDisplay = true
    }

    /// The displayed chips' bounding box inflated by the tray margins, or
    /// `nil` when there is nothing to sit behind.
    static func frame(forDisplayFrames displayFrames: [CGRect]) -> CGRect? {
        guard let group = HoverOverlayGeometry.unionedBounds(of: displayFrames) else {
            return nil
        }
        return CGRect(
            x: group.minX - horizontalMargin,
            y: group.minY - verticalMargin,
            width: group.width + horizontalMargin * 2,
            height: group.height + verticalMargin * 2
        )
    }

    /// Converts an AX-space rect into tray-local AppKit coordinates for the
    /// given tray frame.
    static func localRect(forAXRect rect: CGRect, inTray trayFrame: CGRect) -> CGRect {
        let globalMaxY = AXQuery.coordinatePivotY
        let appKitRect = CGRect(
            x: rect.minX,
            y: globalMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return CGRect(
            x: appKitRect.minX - trayFrame.minX,
            y: appKitRect.minY - (globalMaxY - trayFrame.maxY),
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    /// White rounded-rect mask for `NSVisualEffectView.maskImage`, shared by
    /// every glass-backed overlay panel (tray pill, management HUD).
    static func roundedMaskImage(size: NSSize, radius: CGFloat) -> NSImage {
        GlassBackdrop.roundedMaskImage(size: size, radius: radius)
    }
}

/// Draws the bounded radial glows behind the traffic dots on the glass tray.
final class TrayGlowView: NSView {
    var glows: [HoverOverlayTrayPanel.Glow] = []

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for glow in glows {
            let dotRect = glow.rect
            let srgb = glow.color.usingColorSpace(.sRGB) ?? glow.color
            // The halo extends 0.32 × dot width past the dot edge and fades
            // to zero exactly at the halo's boundary, so the glow always
            // decays fully inside the tray margins.
            let haloRect = dotRect.insetBy(
                dx: -dotRect.width * 0.32,
                dy: -dotRect.height * 0.32
            )
            context.saveGState()
            NSBezierPath(ovalIn: haloRect).addClip()
            let components: [CGFloat] = [
                srgb.redComponent, srgb.greenComponent, srgb.blueComponent, 0.45,
                srgb.redComponent, srgb.greenComponent, srgb.blueComponent, 0,
            ]
            if let gradient = CGGradient(
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                colorComponents: components,
                locations: [0, 1],
                count: 2
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: dotRect.midX, y: dotRect.midY),
                    startRadius: dotRect.width * 0.38,
                    endCenter: CGPoint(x: dotRect.midX, y: dotRect.midY),
                    endRadius: haloRect.width / 2,
                    options: []
                )
            }
            context.restoreGState()
        }
    }
}
