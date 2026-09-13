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
/// The panel is sized to the configured enlarged diameter and centered on the
/// original button's position, so it swallows clicks aimed at the real button
/// and hands them to the controller after the dwell gate passes.
final class HoverOverlayPanel: NSPanel {
    let buttonView: HoverOverlayButtonView

    /// - Parameters:
    ///   - buttonFrame: The original button's frame in AX coordinates.
    ///   - info: The overlayed button's metadata.
    ///   - title: Hover preview text drawn above the button; ignored in
    ///     hotspot mode.
    ///   - enlargedSize: The square panel edge length in points.
    ///   - isHotspot: When `true` the panel draws nothing and activates
    ///     immediately (invisible click zone).
    ///   - onActivate: Called when the user clicks after dwell completion.
    init(
        buttonFrame: CGRect,
        info: OverlayButtonInfo,
        title: String,
        enlargedSize: CGFloat,
        isHotspot: Bool = false,
        onActivate: @escaping () -> Void
    ) {
        let panelFrame = HoverOverlayGeometry.panelFrame(
            forButtonFrame: buttonFrame,
            enlargedSize: enlargedSize
        )
        let globalMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        // Convert the AX (top-left origin) panel frame to AppKit coordinates.
        let appKitFrame = CGRect(
            x: panelFrame.minX,
            y: globalMaxY - panelFrame.maxY,
            width: panelFrame.width,
            height: panelFrame.height
        )
        buttonView = HoverOverlayButtonView(
            frame: NSRect(origin: .zero, size: appKitFrame.size),
            info: info,
            title: title,
            isHotspot: isHotspot,
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
        contentView = buttonView
    }
}

/// Draws one enlarged traffic-light button: colored circle, symbol, dwell
/// progress ring and the hover preview text above the circle. In hotspot
/// mode the view is fully invisible and always activated.
final class HoverOverlayButtonView: NSView {
    private let info: OverlayButtonInfo
    private let title: String
    private let isHotspot: Bool
    private let onActivate: () -> Void
    private var dwellProgress: Double = 0
    private var isActivated = false

    init(
        frame: NSRect,
        info: OverlayButtonInfo,
        title: String,
        isHotspot: Bool = false,
        onActivate: @escaping () -> Void
    ) {
        self.info = info
        self.title = title
        self.isHotspot = isHotspot
        self.onActivate = onActivate
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        drawTitle()
        let circleRect = CGRect(x: 2, y: 1, width: bounds.width - 4, height: bounds.height - 15)
        drawProgressRing(around: circleRect)
        drawCircle(in: circleRect)
        drawSymbol(in: circleRect)
    }

    // MARK: - Drawing

    private var buttonColor: NSColor {
        switch info.button {
        case .close: .systemRed
        case .minimize: .systemYellow
        case .zoom: .systemGreen
        }
    }

    private func drawTitle() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        text.draw(in: CGRect(x: 0, y: bounds.height - 12, width: bounds.width, height: 11))
    }

    private func drawProgressRing(around circleRect: NSRect) {
        guard dwellProgress > 0 else { return }
        let ringRect = circleRect.insetBy(dx: -1.5, dy: -1.5)
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
            radius: ringRect.width / 2,
            startAngle: 90,
            endAngle: 90 - 360 * dwellProgress,
            clockwise: true
        )
        path.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    private func drawCircle(in circleRect: NSRect) {
        buttonColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: circleRect).fill()
    }

    private func drawSymbol(in circleRect: NSRect) {
        let symbolColor = NSColor.black.withAlphaComponent(0.55)
        symbolColor.setStroke()
        symbolColor.setFill()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round

        switch info.button {
        case .close:
            drawCloseCross(into: path, circleRect: circleRect)
            path.stroke()
        case .minimize:
            drawMinusLine(into: path, circleRect: circleRect)
            path.stroke()
        case .zoom:
            drawFullscreenTriangles(into: path, circleRect: circleRect)
            path.fill()
        }
    }

    private func drawCloseCross(into path: NSBezierPath, circleRect: NSRect) {
        path.move(to: NSPoint(x: circleRect.midX - 3, y: circleRect.midY - 3))
        path.line(to: NSPoint(x: circleRect.midX + 3, y: circleRect.midY + 3))
        path.move(to: NSPoint(x: circleRect.midX - 3, y: circleRect.midY + 3))
        path.line(to: NSPoint(x: circleRect.midX + 3, y: circleRect.midY - 3))
    }

    private func drawMinusLine(into path: NSBezierPath, circleRect: NSRect) {
        path.move(to: NSPoint(x: circleRect.midX - 3.5, y: circleRect.midY))
        path.line(to: NSPoint(x: circleRect.midX + 3.5, y: circleRect.midY))
    }

    /// Adds the two outward-pointing triangles used as the fullscreen symbol.
    private func drawFullscreenTriangles(into path: NSBezierPath, circleRect: NSRect) {
        let midY = circleRect.midY
        let leftX = circleRect.midX - 5.5
        let rightX = circleRect.midX + 5.5
        path.move(to: NSPoint(x: leftX, y: midY))
        path.line(to: NSPoint(x: leftX + 4.5, y: midY - 3))
        path.line(to: NSPoint(x: leftX + 4.5, y: midY + 3))
        path.close()
        path.move(to: NSPoint(x: rightX, y: midY))
        path.line(to: NSPoint(x: rightX - 4.5, y: midY - 3))
        path.line(to: NSPoint(x: rightX - 4.5, y: midY + 3))
        path.close()
    }
}
