import AppKit

/// Shared by the live, nonactivating panel and the settings preview.
public enum HoverControlAppearance {
    public static func makePreviewButton(frame: NSRect, action: ButtonAction, color: NSColor) -> NSButton {
        let button = HoverOverlayButtonView(
            frame: frame, symbol: action.extraSymbolName ?? "circle",
            label: action.localizedLabel, color: color, onActivate: { _ in }
        )
        button.setDwellProgress(1)
        return button
    }

    public static func configure(_ button: NSButton, color: NSColor) {
        button.setButtonType(.momentaryPushIn)
        button.controlSize = .large
        button.bezelColor = color
        button.isBordered = false
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        button.contentTintColor = luminance > 0.5 ? .black.withAlphaComponent(0.8) : .white
    }

    /// NSButton's glass bezel loses its tint in a non-key panel. An explicit
    /// glass effect owns the semantic color independently of window activation;
    /// its contentView remains a native button for tracking and accessibility.
    public static func makeSurface(for button: NSButton) -> NSView {
        let bounds = NSRect(origin: .zero, size: button.frame.size)
        let surface = GlassBackdrop.makeView(
            size: button.frame.size, cornerRadius: button.frame.height / 2
        )
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.tintColor = button.bezelColor
        }
        let content = NSView(frame: bounds)
        content.autoresizingMask = [.width, .height]
        // Traffic-light colors are semantic state, not window emphasis. Keep
        // their colored face inside the native glass rim even when AppKit
        // desaturates inactive glass. No custom blur, shadow or glass drawing.
        let face = NSView(frame: bounds.insetBy(dx: 2, dy: 2))
        face.wantsLayer = true
        face.layer?.backgroundColor = button.bezelColor?.cgColor
        face.layer?.cornerRadius = face.frame.height / 2
        face.autoresizingMask = [.width, .height]
        face.setAccessibilityElement(false)
        content.addSubview(face)
        button.frame.origin = .zero
        button.autoresizingMask = [.width, .height]
        content.addSubview(button)
        GlassBackdrop.host(content, in: surface)
        return surface
    }

    /// Glass buttons share one sampling pass instead of sitting on another
    /// glass plate. The container also owns the joining of nearby glass shapes.
    public static func makeGroup(content: NSView, size: NSSize) -> NSView {
        if #available(macOS 26.0, *) {
            let group = NSGlassEffectContainerView(frame: NSRect(origin: .zero, size: size))
            group.wantsLayer = true
            group.spacing = 8
            group.contentView = content
            group.autoresizingMask = [.width, .height]
            return group
        }
        let backdrop = GlassBackdrop.makeView(
            size: size, cornerRadius: size.height / 2, autoresizingMask: [.width, .height]
        )
        GlassBackdrop.host(content, in: backdrop)
        return backdrop
    }
}
