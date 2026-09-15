import AppKit

/// SF Symbol name for each extra-button action; `nil` actions are never
/// rendered so `.none` needs no symbol.
extension ButtonAction {
    var extraSymbolName: String? {
        switch self {
        case .closeWindow: "xmark"
        case .quitApp: "power"
        case .minimize: "minus"
        case .hideApp: "eye.slash"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .almostMaximize: "rectangle.inset.filled"
        case .fullscreen: "arrow.up.backward.and.arrow.down.forward"
        case .tileLeft: "rectangle.lefthalf.inset.filled"
        case .tileRight: "rectangle.righthalf.inset.filled"
        case .tileTop: "rectangle.tophalf.inset.filled"
        case .tileBottom: "rectangle.bottomhalf.inset.filled"
        case .tileTopLeft: "rectangle.topleftthird.inset.filled"
        case .tileTopRight: "rectangle.toprightthird.inset.filled"
        case .tileBottomLeft: "rectangle.bottomleftthird.inset.filled"
        case .tileBottomRight: "rectangle.bottomrightthird.inset.filled"
        case .centerWindow: "rectangle.center.inset.filled"
        case .moveToNextDisplay: "display.2"
        case .none: nil
        case .windowManagerPanel: "rectangle.grid.3x3"
        }
    }
}

/// Borderless, non-activating panel showing one user-configured extra action
/// chip to the right of the traffic lights. Rendering mirrors
/// `HoverOverlayPanel`: on macOS 26+ a circular Liquid Glass chip tinted
/// with the configured glass tint (falling back to the system accent),
/// dwell ring and an action symbol; earlier systems draw an opaque accent
/// circle directly on the glass tray.
final class HoverOverlayExtraPanel: NSPanel {
    let buttonView: HoverOverlayExtraButtonView

    /// - Parameters:
    ///   - panelFrame: The panel's frame in AX coordinates (from the group
    ///     layout).
    ///   - action: The action performed when the chip is clicked.
    ///   - tintColor: User-configured glass tint, or `nil` for the system
    ///     accent.
    ///   - onActivate: Called when the user clicks after dwell completion.
    init(
        panelFrame: CGRect,
        action: ButtonAction,
        tintColor: NSColor? = nil,
        onActivate: @escaping () -> Void
    ) {
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        // Convert the AX (top-left origin) panel frame to AppKit coordinates.
        let appKitFrame = CGRect(
            x: panelFrame.minX,
            y: globalMaxY - panelFrame.maxY,
            width: panelFrame.width,
            height: panelFrame.height
        )
        buttonView = HoverOverlayExtraButtonView(
            frame: NSRect(origin: .zero, size: appKitFrame.size),
            action: action,
            tintColor: tintColor,
            onActivate: onActivate
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
        contentView = Self.makeContentView(buttonView: buttonView, tintColor: tintColor)
    }

    /// Layers the button view on a circular glass chip (macOS 26+); before
    /// 26 the button view draws its own opaque circle and needs no backdrop.
    private static func makeContentView(
        buttonView: HoverOverlayExtraButtonView,
        tintColor: NSColor?
    ) -> NSView {
        guard #available(macOS 26.0, *) else {
            return buttonView
        }
        let container = NSView(frame: buttonView.bounds)
        let circleRect = OverlayChipDrawing.circleRect(in: container.bounds)
        let glass = NSGlassEffectView(frame: circleRect)
        glass.cornerRadius = circleRect.width / 2
        glass.tintColor = tintColor ?? .controlAccentColor
        container.addSubview(glass)
        buttonView.usesGlassFill = true
        container.addSubview(buttonView)
        return container
    }
}

/// Draws one extra action chip: accent circle (or the glass chip beneath it
/// on macOS 26+), SF Symbol and dwell progress ring — the same chip language
/// as the enlarged traffic lights.
final class HoverOverlayExtraButtonView: NSView {
    private let action: ButtonAction
    private let onActivate: () -> Void
    /// The user's glass tint overrides the system accent when configured.
    private var customTintColor: NSColor?
    private var dwellProgress: Double = 0
    private var isActivated = false
    /// When `true` a circular `NSGlassEffectView` sits behind this view and
    /// provides the chip's fill, so `draw` skips the opaque circle. Set by
    /// the panel when it installs the glass backdrop.
    var usesGlassFill = false

    init(
        frame: NSRect,
        action: ButtonAction,
        tintColor: NSColor? = nil,
        onActivate: @escaping () -> Void
    ) {
        self.action = action
        self.onActivate = onActivate
        customTintColor = tintColor
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The chip's semantic color — the configured tint, or the system accent
    /// — used for the dwell ring and the fallback opaque circle.
    var accentColor: NSColor {
        customTintColor ?? .controlAccentColor
    }

    func setDwellProgress(_ progress: Double) {
        dwellProgress = min(max(progress, 0), 1)
        isActivated = dwellProgress >= 1
        needsDisplay = true
    }

    func resetDwell() {
        dwellProgress = 0
        isActivated = false
        needsDisplay = true
    }

    override func mouseDown(with _: NSEvent) {
        // Same contract as the traffic chips: the interceptor's tap sees the
        // raw event first; arm the gate so it passes the click through.
        OverlayClickGate.suppressFor(milliseconds: 500)
        guard isActivated else { return }
        onActivate()
    }

    override func draw(_: NSRect) {
        let circleRect = OverlayChipDrawing.circleRect(in: bounds)
        OverlayChipDrawing.drawProgressRing(around: circleRect, progress: dwellProgress)
        if !usesGlassFill {
            OverlayChipDrawing.drawCircle(in: circleRect, color: accentColor)
        }
        drawSymbol(in: circleRect)
    }

    private func drawSymbol(in circleRect: NSRect) {
        guard let symbolName = action.extraSymbolName else { return }
        let pointSize = circleRect.width * 0.38
        let configured = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        guard let configured else { return }
        let image = configured
        image.isTemplate = true
        // Matches the traffic chips' 55% black symbol ink.
        let symbolRect = CGRect(
            x: circleRect.midX - image.size.width / 2,
            y: circleRect.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 0.55)
    }
}

// MARK: - Dwell panel conformance

extension HoverOverlayExtraPanel: OverlayDwellPanel {
    func setDwellProgress(_ progress: Double) {
        buttonView.setDwellProgress(progress)
    }

    func resetDwell() {
        buttonView.resetDwell()
    }
}
