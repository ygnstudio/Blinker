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
/// .panelFrames`) so enlarged neighbors never overlap. The dot is an opaque
/// vivid circle with a hairline rim; the glass capsule tray behind it
/// (`HoverOverlayTrayPanel`) provides the chip's backdrop on every OS.
final class HoverOverlayPanel: NSPanel {
    let buttonView: HoverOverlayButtonView

    /// - Parameters:
    ///   - panelFrame: The panel's frame in AX coordinates (from the group
    ///     layout).
    ///   - info: The overlayed button's metadata.
    ///   - isHotspot: When `true` the panel draws nothing and activates
    ///     immediately (invisible click zone).
    ///   - onActivate: Called with the click's variant when the user clicks
    ///     after dwell completion (long presses report through `onLongPress`).
    ///   - onLongPress: Called when a plain left click is held past the
    ///     long-press threshold.
    init(
        panelFrame: CGRect,
        info: OverlayButtonInfo,
        isHotspot: Bool = false,
        onActivate: @escaping (ClickVariant) -> Void,
        onLongPress: @escaping () -> Void
    ) {
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
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
            isHotspot: isHotspot,
            onActivate: onActivate,
            onLongPress: onLongPress
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

/// Draws one enlarged traffic-light button: opaque vivid circle, symbol and
/// dwell progress ring. In hotspot mode the view is fully invisible and
/// always activated.
final class HoverOverlayButtonView: NSView {
    private let info: OverlayButtonInfo
    private let isHotspot: Bool
    private let onActivate: (ClickVariant) -> Void
    private let onLongPress: () -> Void
    private var dwellProgress: Double = 0
    private var isActivated = false
    /// Pending plain left click waiting to resolve as a quick click (mouse
    /// up) or a long press (timer). Mirrors the interceptor's behavior for
    /// buttons whose long-press slot is configured.
    private var pressStartedAt: Date?
    private var longPressTimer: Timer?

    init(
        frame: NSRect,
        info: OverlayButtonInfo,
        isHotspot: Bool = false,
        onActivate: @escaping (ClickVariant) -> Void,
        onLongPress: @escaping () -> Void
    ) {
        self.info = info
        self.isHotspot = isHotspot
        self.onActivate = onActivate
        self.onLongPress = onLongPress
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The button's semantic color, also used for the tray glow behind it.
    var accentColor: NSColor {
        OverlayChipDrawing.vividColor(for: info.button)
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

    override func mouseDown(with event: NSEvent) {
        // This click is consumed here, but the interceptor's tap sees the raw
        // event first; arm the gate so it passes the click through instead of
        // performing the mapped action a second time.
        OverlayClickGate.suppressFor(milliseconds: 500)
        guard isActivated || isHotspot else { return }

        let variant = Self.variant(of: event)
        guard variant == .left else {
            onActivate(variant)
            return
        }
        // Plain left click: wait for release — a hold past the threshold is
        // a long press instead. The controller ignores `onLongPress` when no
        // long-press slot is configured, so scheduling unconditionally is safe.
        pressStartedAt = Date()
        let threshold = TrafficLightInterceptor.longPressThreshold
        let timer = Timer(timeInterval: threshold, repeats: false) { [weak self] _ in
            self?.fireLongPress()
        }
        longPressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Fires when a left click stays held past the long-press threshold.
    private func fireLongPress() {
        guard pressStartedAt != nil else { return }
        pressStartedAt = nil
        longPressTimer = nil
        onLongPress()
    }

    override func mouseUp(with _: NSEvent) {
        // A click that outlived the threshold already fired as a long press
        // (fireLongPress clears the pending state before this runs).
        guard pressStartedAt != nil else { return }
        pressStartedAt = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        onActivate(.left)
    }

    override func rightMouseDown(with _: NSEvent) {
        OverlayClickGate.suppressFor(milliseconds: 500)
        guard isActivated || isHotspot else { return }
        onActivate(.right)
    }

    /// Maps an NSEvent's modifiers to a click variant (⌥ first, then 🌐),
    /// matching the interceptor's `CGEventFlags` logic.
    private static func variant(of event: NSEvent) -> ClickVariant {
        let flags = event.modifierFlags
        if flags.contains(.option) {
            return .optionLeft
        }
        if flags.contains(.function) {
            return .globeLeft
        }
        return .left
    }

    override func draw(_: NSRect) {
        guard !isHotspot else { return }
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
