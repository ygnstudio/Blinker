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

    /// Present the material and its content together, without delayed alpha changes.
    public func orderFrontFadingIn(hold _: TimeInterval = 0, duration _: TimeInterval = 0) {
        alphaValue = 1
        orderFrontRegardless()
    }
}

/// Shared system glass for contextual controls and floating feedback.
public enum GlassBackdrop {
    /// The caller owns layout; content belongs in the returned glass contentView.
    public static func makeView(
        size: NSSize,
        cornerRadius: CGFloat,
        style: NSGlassEffectView.Style = .regular,
        autoresizingMask: NSView.AutoresizingMask = []
    ) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = cornerRadius
        glass.style = style
        #if compiler(>=6.4)
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = true
            }
        #endif
        glass.autoresizingMask = autoresizingMask
        return glass
    }
}
