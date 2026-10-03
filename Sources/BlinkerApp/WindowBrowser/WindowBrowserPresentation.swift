import AppKit
import BlinkerCore
import SwiftUI

/// Owns the native surface; catalog refreshes update the existing SwiftUI host.
@MainActor
final class WindowBrowserPresentation {
    private(set) var panel: WindowBrowserPanel?
    private var departurePanel: OverlayPanel?
    private var surface: NSView?
    private let fade = WindowBrowserFade()

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
            self.surface = surface
            self.panel = panel
        }
        guard let panel else { return }
        if let surface, surface.window !== panel {
            departurePanel?.contentView = nil
            panel.contentView = surface
        }
        panel.ignoresMouseEvents = false
        surface?.setAccessibilityHidden(false)
        panel.setFrame(frame, display: true)
        updateCornerRadius(scale: scale)
        panel.invalidateShadow()
        fade.show(panel) {
            if dockMode {
                panel.orderFrontRegardless()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func hide(completion: @escaping () -> Void) {
        guard let panel, let surface else { completion(); return }
        panel.ignoresMouseEvents = true
        surface.setAccessibilityHidden(true)
        guard panel.isVisible else {
            // AppKit may already have hidden the app. Retire the transition
            // without showing an exit surface or leaving the next show gated.
            fade.hide(panel, animated: false, completion: completion)
            return
        }
        if departurePanel == nil {
            departurePanel = OverlayPanel(appKitFrame: panel.frame, ignoresMouseEvents: true)
            departurePanel?.hasShadow = true
        }
        guard let departurePanel else { completion(); return }
        departurePanel.setFrame(panel.frame, display: false)
        // Reuse the live view for the brief exit. No bitmap copy or screen
        // sampling; ordering out the interactive panel releases keyboard focus now.
        panel.contentView = nil
        departurePanel.contentView = surface
        panel.orderOut(nil)
        fade.hide(departurePanel, completion: completion)
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
