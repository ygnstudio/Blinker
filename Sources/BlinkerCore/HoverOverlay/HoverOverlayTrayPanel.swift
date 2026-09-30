import AppKit

/// A single nonactivating window owns the glass and all of its controls.
/// No sampled pixels, masking glows or independently composited button windows.
final class HoverOverlayTrayPanel: OverlayPanel {
    private let controlsView: NSView
    private let backdrop: NSView

    init(trayFrame: CGRect) {
        let frame = AXQuery.appKitFrame(fromAXRect: trayFrame)
        let controls = NSView(frame: NSRect(origin: .zero, size: frame.size))
        controls.autoresizingMask = [.width, .height]
        controlsView = controls
        backdrop = HoverControlAppearance.makeGroup(content: controls, size: frame.size)
        super.init(appKitFrame: frame)
        hasShadow = true
        contentView = backdrop
    }

    func update(trayFrame: CGRect, controls: [NSButton], frames: [CGRect]) {
        setFrame(AXQuery.appKitFrame(fromAXRect: trayFrame), display: false)
        controlsView.subviews.forEach { $0.removeFromSuperview() }
        for (control, frame) in zip(controls, frames) {
            control.frame = CGRect(origin: .zero, size: frame.size)
            let surface = HoverControlAppearance.makeSurface(for: control)
            surface.frame = Self.localRect(forAXRect: frame, inTray: trayFrame)
            controlsView.addSubview(surface)
        }
        invalidateShadow()
    }

    static func frame(forDisplayFrames frames: [CGRect]) -> CGRect? {
        HoverOverlayGeometry.unionedBounds(of: frames)?.insetBy(
            dx: -HoverOverlayGeometry.trayHorizontalPadding, dy: -HoverOverlayGeometry.trayVerticalPadding
        )
    }

    static func localRect(forAXRect rect: CGRect, inTray trayFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - trayFrame.minX, y: trayFrame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }
}
