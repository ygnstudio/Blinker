import AppKit

/// Backdrop panel that covers the native traffic-light buttons while the
/// enlarged overlay is visible, so the small originals don't peek through
/// the gaps between enlarged chips.
///
/// On macOS 26+ the backdrop is a system Liquid Glass effect view with no
/// tint: its heavy blur smears the native buttons into whatever is behind
/// the window, so the pill blends with the real background instead of
/// looking like a flat gray capsule. Earlier systems fall back to a neutral
/// `underWindowBackground` material pill. The panel sits one window level
/// below the enlarged chips and is ordered before them, so the chips always
/// render on top. It is created only in overlay mode; hotspot mode keeps
/// the title bar untouched.
final class HoverOverlayMaskPanel: NSPanel {
    /// Extra coverage (pt) around the native buttons' bounding box so the
    /// originals are fully hidden, not just their exact frames.
    static let padding: CGFloat = 4

    /// - Parameter maskFrame: The frame to cover, in AX coordinates — the
    ///   native buttons' bounding box inflated by `padding`.
    init(maskFrame: CGRect) {
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitFrame = CGRect(
            x: maskFrame.minX,
            y: globalMaxY - maskFrame.maxY,
            width: maskFrame.width,
            height: maskFrame.height
        )
        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // One level below the enlarged chips: the backdrop must never cover
        // them, no matter the fronting order, while staying above regular
        // app windows.
        level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = false

        let size = appKitFrame.size
        // Pill shape: the corner radius is derived from the frame height.
        let radius = size.height / 2
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = radius
            contentView = glass
        } else {
            let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            backdrop.material = .underWindowBackground
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.maskImage = Self.pillMaskImage(size: size, radius: radius)
            contentView = backdrop
        }
    }

    /// The native buttons' bounding box inflated by the mask padding, or
    /// `nil` when there are no buttons to cover.
    static func frame(forButtonFrames buttonFrames: [CGRect]) -> CGRect? {
        guard let group = HoverOverlayGeometry.unionedBounds(of: buttonFrames) else {
            return nil
        }
        return group.insetBy(dx: -padding, dy: -padding)
    }

    private static func pillMaskImage(size: NSSize, radius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }
}
