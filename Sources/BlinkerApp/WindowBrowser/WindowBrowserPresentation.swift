import AppKit
import BlinkerCore
import SwiftUI

/// Owns the native surface; catalog refreshes update the existing SwiftUI host.
@MainActor
final class WindowBrowserPresentation {
    private(set) var panel: WindowBrowserPanel?

    func show(controller: WindowBrowserController, thumbnails: WindowThumbnailStore,
              frame: CGRect, scale: CGFloat, dockMode: Bool) {
        if panel == nil {
            let panel = WindowBrowserPanel(appKitFrame: frame)
            panel.hasShadow = true
            let host = NSHostingView(rootView: WindowBrowserView(
                controller: controller, thumbnails: thumbnails
            ))
            host.frame = CGRect(origin: .zero, size: frame.size)
            host.autoresizingMask = [.width, .height]
            let backdrop = GlassBackdrop.makeView(size: frame.size, cornerRadius: 24 * scale,
                                                  autoresizingMask: [.width, .height])
            GlassBackdrop.host(host, in: backdrop)
            let surface = NSView(frame: CGRect(origin: .zero, size: frame.size))
            surface.wantsLayer = true
            surface.layer?.masksToBounds = true
            surface.addSubview(backdrop)
            panel.contentView = surface
            self.panel = panel
        }
        guard let panel else { return }
        panel.setFrame(frame, display: true)
        updateCornerRadius(scale: scale)
        panel.invalidateShadow()
        if dockMode {
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func updateCornerRadius(scale: CGFloat) {
        guard let surface = panel?.contentView, let backdrop = surface.subviews.first else { return }
        surface.layer?.cornerRadius = 24 * scale
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = 24 * scale
        } else if let visual = backdrop as? NSVisualEffectView {
            visual.maskImage = GlassBackdrop.roundedMaskImage(size: surface.bounds.size, radius: 24 * scale)
        }
    }
}
