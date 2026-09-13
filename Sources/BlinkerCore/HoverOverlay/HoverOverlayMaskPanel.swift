import AppKit

/// Backdrop panel that covers the native traffic-light buttons while the
/// enlarged overlay is visible, so the small originals don't peek through
/// the gaps between enlarged chips.
///
/// The backdrop uses the titlebar material so it blends with the host
/// window's chrome, shaped as a pill matching the chip aesthetics. It sits
/// at the same level as the enlarged panels but is ordered first, so the
/// enlarged chips render on top. The panel is created only in overlay mode;
/// hotspot mode keeps the title bar untouched.
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
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = false

        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: appKitFrame.size))
        backdrop.material = .titlebar
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        // Pill shape: the mask image stretches with the (per-rebuild fixed)
        // size, so the corner radius is derived from the frame height.
        let radius = appKitFrame.height / 2
        backdrop.maskImage = Self.pillMaskImage(size: appKitFrame.size, radius: radius)
        contentView = backdrop
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
