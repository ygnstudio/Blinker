import AppKit

/// Metadata describing one overlayed traffic-light button.
struct OverlayButtonInfo {
    /// The semantic button (close / minimize / zoom).
    let button: TrafficButton
    /// The AX subrole of the underlying button, used for native AXPress.
    let axSubrole: String
    /// Button frame in AX (top-left origin) global coordinates.
    let frame: CGRect
}

/// Borderless, non-activating panel showing one enlarged traffic-light button.
///
/// The panel frame comes from the group layout (`HoverOverlayGeometry
/// .panelFrames`) so enlarged neighbors never overlap. On macOS 26+ the chip
/// behind the button is a system Liquid Glass effect view; earlier systems
/// fall back to a translucent backdrop drawn by the button view itself.
final class HoverOverlayPanel: NSPanel {
    let buttonView: HoverOverlayButtonView

    /// - Parameters:
    ///   - panelFrame: The panel's frame in AX coordinates (from the group
    ///     layout).
    ///   - info: The overlayed button's metadata.
    ///   - isHotspot: When `true` the panel draws nothing and activates
    ///     immediately (invisible click zone).
    ///   - onActivate: Called when the user clicks after dwell completion.
    init(
        panelFrame: CGRect,
        info: OverlayButtonInfo,
        isHotspot: Bool = false,
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
        var usesSystemGlass = false
        if #available(macOS 26.0, *), !isHotspot {
            usesSystemGlass = true
        }
        buttonView = HoverOverlayButtonView(
            frame: NSRect(origin: .zero, size: appKitFrame.size),
            info: info,
            isHotspot: isHotspot,
            usesSystemGlass: usesSystemGlass,
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
        if #available(macOS 26.0, *), !isHotspot {
            let glassView = NSGlassEffectView(frame: appKitFrame)
            glassView.cornerRadius = min(18, panelFrame.width * 0.3)
            glassView.tintColor = buttonView.accentColor
            glassView.contentView = buttonView
            contentView = glassView
        } else {
            contentView = buttonView
        }
    }
}

/// Draws one enlarged traffic-light button: colored circle, symbol and dwell
/// progress ring. In hotspot mode the view is fully invisible and always
/// activated.
final class HoverOverlayButtonView: NSView {
    private let info: OverlayButtonInfo
    private let isHotspot: Bool
    /// When `true` the panel wraps this view in `NSGlassEffectView`, so the
    /// view only draws circle, symbol and text — the chip is system glass.
    private let usesSystemGlass: Bool
    private let onActivate: () -> Void
    private var dwellProgress: Double = 0
    private var isActivated = false

    init(
        frame: NSRect,
        info: OverlayButtonInfo,
        isHotspot: Bool = false,
        usesSystemGlass: Bool = false,
        onActivate: @escaping () -> Void
    ) {
        self.info = info
        self.isHotspot = isHotspot
        self.usesSystemGlass = usesSystemGlass
        self.onActivate = onActivate
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The button's semantic color, also used as the glass tint on macOS 26+.
    var accentColor: NSColor {
        switch info.button {
        case .close: .systemRed
        case .minimize: .systemYellow
        case .zoom: .systemGreen
        }
    }

    /// Updates the dwell progress (0...1); the button becomes clickable at 1.
    func setDwellProgress(_ progress: Double) {
        dwellProgress = min(max(progress, 0), 1)
        isActivated = dwellProgress >= 1
        needsDisplay = true
    }

    /// Resets dwell state after the cursor leaves the panel.
    func resetDwell() {
        dwellProgress = 0
        isActivated = false
        needsDisplay = true
    }

    override func mouseDown(with _: NSEvent) {
        // This click is consumed here, but the interceptor's tap sees the raw
        // event first; arm the gate so it passes the click through instead of
        // performing the mapped action a second time.
        OverlayClickGate.suppressFor(milliseconds: 500)
        guard isActivated || isHotspot else { return }
        onActivate()
    }

    override func draw(_: NSRect) {
        guard !isHotspot else { return }
        if !usesSystemGlass {
            OverlayChipDrawing.drawBackdropChip(in: bounds)
        }
        let circleRect = OverlayChipDrawing.circleRect(in: bounds)
        OverlayChipDrawing.drawProgressRing(around: circleRect, progress: dwellProgress)
        OverlayChipDrawing.drawCircle(in: circleRect, color: accentColor)
        drawSymbol(in: circleRect)
    }

    // MARK: - Drawing

    private func drawSymbol(in circleRect: NSRect) {
        let symbolColor = NSColor.black.withAlphaComponent(0.55)
        symbolColor.setStroke()
        symbolColor.setFill()
        let path = NSBezierPath()
        // Symbols scale with the circle; the constants below were designed
        // for a 28 pt diameter.
        let scale = circleRect.width / 28
        path.lineWidth = max(1.4, 1.6 * scale)
        path.lineCapStyle = .round

        switch info.button {
        case .close:
            drawCloseCross(into: path, circleRect: circleRect, scale: scale)
            path.stroke()
        case .minimize:
            drawMinusLine(into: path, circleRect: circleRect, scale: scale)
            path.stroke()
        case .zoom:
            drawFullscreenTriangles(into: path, circleRect: circleRect, scale: scale)
            path.fill()
        }
    }

    private func drawCloseCross(into path: NSBezierPath, circleRect: NSRect, scale: CGFloat) {
        let halfExtent = 3 * scale
        path.move(to: NSPoint(x: circleRect.midX - halfExtent, y: circleRect.midY - halfExtent))
        path.line(to: NSPoint(x: circleRect.midX + halfExtent, y: circleRect.midY + halfExtent))
        path.move(to: NSPoint(x: circleRect.midX - halfExtent, y: circleRect.midY + halfExtent))
        path.line(to: NSPoint(x: circleRect.midX + halfExtent, y: circleRect.midY - halfExtent))
    }

    private func drawMinusLine(into path: NSBezierPath, circleRect: NSRect, scale: CGFloat) {
        let halfExtent = 3.5 * scale
        path.move(to: NSPoint(x: circleRect.midX - halfExtent, y: circleRect.midY))
        path.line(to: NSPoint(x: circleRect.midX + halfExtent, y: circleRect.midY))
    }

    /// Adds the two outward-pointing triangles used as the fullscreen symbol.
    private func drawFullscreenTriangles(into path: NSBezierPath, circleRect: NSRect, scale: CGFloat) {
        let midY = circleRect.midY
        let leftX = circleRect.midX - 5.5 * scale
        let rightX = circleRect.midX + 5.5 * scale
        let halfHeight = 3 * scale
        let depth = 4.5 * scale
        path.move(to: NSPoint(x: leftX, y: midY))
        path.line(to: NSPoint(x: leftX + depth, y: midY - halfHeight))
        path.line(to: NSPoint(x: leftX + depth, y: midY + halfHeight))
        path.close()
        path.move(to: NSPoint(x: rightX, y: midY))
        path.line(to: NSPoint(x: rightX - depth, y: midY - halfHeight))
        path.line(to: NSPoint(x: rightX - depth, y: midY + halfHeight))
        path.close()
    }
}

// MARK: - Dwell panel conformance

extension HoverOverlayPanel: OverlayDwellPanel {
    func setDwellProgress(_ progress: Double) {
        buttonView.setDwellProgress(progress)
    }

    func resetDwell() {
        buttonView.resetDwell()
    }
}
