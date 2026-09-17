import AppKit

/// Borderless, non-activating floating panel shared by every overlay
/// surface (enlarged chips, extra chips, tray, management HUD, snap
/// preview): transparent, shadowless and always above regular app windows.
public class OverlayPanel: NSPanel {
    /// - Parameters:
    ///   - appKitFrame: The panel frame in AppKit (bottom-left origin)
    ///     coordinates.
    ///   - level: Window level; overlay surfaces stack around `.popUpMenu`.
    ///   - ignoresMouseEvents: Pass `true` for purely visual, click-through
    ///     panels (tray, snap preview).
    public init(
        appKitFrame: CGRect,
        level: NSWindow.Level = .popUpMenu,
        ignoresMouseEvents: Bool = false
    ) {
        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        hasShadow = false
        isReleasedWhenClosed = false
        self.ignoresMouseEvents = ignoresMouseEvents
    }

    /// Orders the panel front with a two-phase fade-in. The system glass
    /// renders its unblended base color — a solid light-or-dark rectangle,
    /// depending on appearance — for an indeterminate stretch after the
    /// window first appears, until the behind-window blend engages (no
    /// public signal announces readiness). A fast or ease-out fade reveals
    /// that base mid-ramp: the pill reads as "white, then translucent".
    ///
    /// Phase one holds the window at zero alpha for `hold` seconds, so the
    /// blend settles while the panel is fully invisible. Phase two fades
    /// in with an ease-in curve, whose near-zero early frames act as extra
    /// insurance against a slower-than-expected blend. Only for glass-backed
    /// surfaces (tray, management HUD): plain drawn panels (chips, snap
    /// preview) have no unblended frame to hide.
    public func orderFrontFadingIn(hold: TimeInterval = 0.2, duration: TimeInterval = 0.3) {
        alphaValue = 0
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.isVisible else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 1
            }
        }
    }
}

/// The glass backdrop shared by the tray, the management HUD and the settings
/// preview card: native `NSGlassEffectView` on macOS 26+, with a masked
/// `NSVisualEffectView` fallback below.
public enum GlassBackdrop {
    /// Builds the backdrop view for the given size and corner radius. The
    /// caller owns layout: position the returned view in its container (or
    /// pass `autoresizingMask` so it follows container resizes).
    public static func makeView(
        size: NSSize,
        cornerRadius: CGFloat,
        autoresizingMask: NSView.AutoresizingMask = []
    ) -> NSView {
        let frame = NSRect(origin: .zero, size: size)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.autoresizingMask = autoresizingMask
            return glass
        }
        let backdrop = NSVisualEffectView(frame: frame)
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = roundedMaskImage(size: size, radius: cornerRadius)
        backdrop.autoresizingMask = autoresizingMask
        return backdrop
    }

    /// White rounded-rect mask for `NSVisualEffectView.maskImage`, shared by
    /// every pre-26 glass fallback.
    public static func roundedMaskImage(size: NSSize, radius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }
}
