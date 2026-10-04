// Adapted from Status Trio by lingyired (Apache-2.0).
// Source: Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift
// Commit: d1672377a172ee4cb4af53d5054610c407c0d34f
// Modified for Blinker: shared configurable glyph, dynamic 1024-point artwork,
// system/light/dark or genuinely transparent background, no raster buffer cache.
// See ThirdParty/StatusTrio for the license and attribution.

import AppKit

enum DockIconRenderer {
    static let size: CGFloat = 1024

    static func image(
        snapshot: MenuBarSystemSnapshot,
        configuration: MenuBarConfiguration = .init(),
        appearance: NSAppearance? = nil
    ) -> NSImage {
        let configuration = configuration.normalized()
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let resolvedAppearance: NSAppearance? = switch configuration.dockBackground {
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            case .system, .transparent: appearance
            }
            let draw = {
                Self.draw(snapshot: snapshot, configuration: configuration,
                          appearance: resolvedAppearance, in: context)
            }
            if let resolvedAppearance {
                resolvedAppearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(
        snapshot: MenuBarSystemSnapshot, configuration: MenuBarConfiguration,
        appearance: NSAppearance?, in context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        if configuration.dockBackground != .transparent {
            drawBackground(in: context)
        }
        // Use the upstream glyph position, including its half-unit optical correction.
        let glyphRect = CGRect(x: 194.8, y: 1024 - 171.84 - 672, width: 672, height: 672)
        let glyph = TrioIconRenderer.image(snapshot: snapshot, size: glyphRect.width,
                                           appearance: appearance, configuration: configuration)
        glyph.draw(in: glyphRect)
    }

    private static func drawBackground(in context: CGContext) {
        let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)
        let isDark = (foreground?.brightnessComponent ?? 1) > 0.5
        let body = isDark
            ? CGColor(red: 21.0 / 255, green: 21.0 / 255, blue: 23.0 / 255, alpha: 1)
            : CGColor(gray: 1, alpha: 1)
        let border = isDark
            ? CGColor(red: 58.0 / 255, green: 58.0 / 255, blue: 61.0 / 255, alpha: 1)
            : CGColor(red: 210.0 / 255, green: 210.0 / 255, blue: 215.0 / 255, alpha: 1)
        context.setFillColor(body)
        context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                               cornerWidth: 210, cornerHeight: 210, transform: nil))
        context.fillPath()
        context.setStrokeColor(border)
        context.setLineWidth(2)
        context.addPath(CGPath(roundedRect: CGRect(x: 65, y: 65, width: 894, height: 894),
                               cornerWidth: 209, cornerHeight: 209, transform: nil))
        context.strokePath()
    }
}
