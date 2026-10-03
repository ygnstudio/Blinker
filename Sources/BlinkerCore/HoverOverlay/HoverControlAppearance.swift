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
        // Keep the semantic face opaque so dark backdrops cannot muddy its color.
        // The inset leaves the native glass rim exposed, including in inactive panels.
        let face = SemanticGlassFace(frame: bounds.insetBy(dx: 2, dy: 2), color: button.bezelColor ?? .clear)
        face.autoresizingMask = [.width, .height]
        face.setAccessibilityElement(false)
        let content = HoverButtonPressFeedback(frame: bounds, face: face)
        if let hoverButton = button as? HoverOverlayButtonView {
            hoverButton.onHoverChanged = { [weak content] hovered, animated in
                content?.setHovered(
                    hovered, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    animated: animated
                )
            }
            hoverButton.onPressChanged = { [weak content] pressed, animated in
                content?.setPressed(
                    pressed, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    animated: animated
                )
            }
        }
        button.frame.origin = .zero
        button.autoresizingMask = [.width, .height]
        content.addSubview(button)
        GlassBackdrop.host(content, in: surface)
        return surface
    }

    /// The effect container only groups button materials; it does not draw a
    /// tray. A separate continuous capsule underneath gives the whole palette
    /// a visible base, including the gaps and outer padding.
    public static func makeGroup(content: NSView, size: NSSize) -> NSView {
        let controls: NSView
        if #available(macOS 26.0, *) {
            let group = NSGlassEffectContainerView(frame: NSRect(origin: .zero, size: size))
            group.wantsLayer = true
            group.spacing = 2
            group.contentView = content
            controls = group
        } else {
            controls = content
        }
        return GlassTrayGroupView(controls: controls, size: size)
    }
}

/// Keep the continuous tray and button glass as siblings in one window so the
/// tray is not nested around the button materials. Both share the same bounds.
private final class GlassTrayGroupView: NSView {
    private let backdrop: NSView
    private let controls: NSView

    init(controls: NSView, size: NSSize) {
        self.controls = controls
        backdrop = GlassBackdrop.makeView(size: size, cornerRadius: size.height / 2)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        autoresizingMask = [.width, .height]
        backdrop.setAccessibilityElement(false)
        addSubview(backdrop)
        addSubview(controls)
        resizeContents()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeContents()
    }

    private func resizeContents() {
        backdrop.frame = bounds
        controls.frame = bounds
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = bounds.height / 2
        } else if let effect = backdrop as? NSVisualEffectView {
            effect.maskImage = GlassBackdrop.roundedMaskImage(size: bounds.size, radius: bounds.height / 2)
        }
    }
}

private final class SemanticGlassFace: NSView {
    private let color: NSColor

    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = color.withAlphaComponent(1).cgColor
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }
}
