import AppKit

struct OverlayButtonInfo {
    let button: TrafficButton
    let axSubrole: String
    let frame: CGRect
}

/// AppKit owns button drawing, accessibility and press/release tracking.
/// The subclass adds only dwell gating and configurable click variants.
final class HoverOverlayButtonView: NSButton, OverlayDwellPanel {
    override static var cellClass: AnyClass? {
        get { HoverOverlayButtonCell.self }
        set {}
    }

    private let hasLongPressAction: () -> Bool
    private let onActivate: (ClickVariant) -> Void
    private let onLongPress: () -> Void
    private let pointerLocationInWindow: (NSWindow) -> NSPoint
    var requiresDwell: (ClickVariant) -> Bool = { _ in true }
    var onPressChanged: (_ pressed: Bool, _ animated: Bool) -> Void = { _, _ in }
    var onHoverChanged: (_ hovered: Bool, _ animated: Bool) -> Void = { _, _ in }
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var dwellProgress: Double = 0
    private let dwellIndicator = HoverDwellIndicatorView()
    private var clickVariant: ClickVariant = .left
    private var didFireLongPress = false
    private var longPressTimer: Timer?
    private var isTrackingMouse = false
    private var wasTrackingCancelled = false

    init(
        frame: NSRect,
        symbol: String,
        label: String,
        color: NSColor,
        hasLongPressAction: @escaping () -> Bool = { false },
        onActivate: @escaping (ClickVariant) -> Void,
        onLongPress: @escaping () -> Void = {},
        pointerLocationInWindow: @escaping (NSWindow) -> NSPoint = {
            $0.convertPoint(fromScreen: NSEvent.mouseLocation)
        }
    ) {
        self.hasLongPressAction = hasLongPressAction
        self.onActivate = onActivate
        self.onLongPress = onLongPress
        self.pointerLocationInWindow = pointerLocationInWindow
        super.init(frame: frame)
        title = ""
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly
        HoverControlAppearance.configure(self, color: color)
        dwellIndicator.frame = bounds
        dwellIndicator.autoresizingMask = [.width, .height]
        dwellIndicator.setAccessibilityElement(false)
        addSubview(dwellIndicator)
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(activateButton)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func updatePresentation(_ presentation: OverlayActionPresentation) {
        toolTip = presentation.label
        setAccessibilityLabel(presentation.label)
        image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: presentation.label)
    }

    func setDwellProgress(_ progress: Double) {
        let value = min(max(progress, 0), 1)
        guard dwellProgress != value else { return }
        dwellProgress = value
        dwellIndicator.progress = requiresDwell(OverlayActionPresentation.variant(for: NSEvent.modifierFlags))
            ? value : 0
    }

    func resetDwell() {
        cancelLongPress()
        setDwellProgress(0)
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                cancelTracking()
            }
            refreshHoverState(animated: false)
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        cancelTracking()
        setHovered(false, animated: false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            cancelTracking()
            setHovered(false, animated: false)
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
            if let newWindow {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowVisibilityChanged),
                    name: NSWindow.didChangeOcclusionStateNotification, object: newWindow
                )
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverState(animated: false)
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshHoverState(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // On unclipped AppKit views visibleRect may extend beyond bounds.
        // Keep hover inside the same fixed rectangle as button tracking.
        let rect = bounds.intersection(visibleRect)
        if hoverTrackingArea?.rect != rect {
            if let hoverTrackingArea {
                removeTrackingArea(hoverTrackingArea)
            }
            let area = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            hoverTrackingArea = area
        }
        refreshHoverState(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(isEnabled && !isHiddenOrHasHiddenAncestor && window?.isVisible == true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false, animated: true)
    }

    @objc private func windowVisibilityChanged() {
        refreshHoverState(animated: false)
    }

    private func refreshHoverState(animated: Bool) {
        guard isEnabled, !isHiddenOrHasHiddenAncestor, let window, window.isVisible else {
            setHovered(false, animated: animated)
            return
        }
        let point = convert(pointerLocationInWindow(window), from: nil)
        setHovered(bounds.contains(point) && visibleRect.contains(point), animated: animated)
    }

    /// The live controller already knows the hovered chip when ordering a new
    /// palette. Seed that state even if no mouse-enter event follows the show.
    func updatePointerHover(_ hovered: Bool) {
        setHovered(hovered && isEnabled && !isHiddenOrHasHiddenAncestor, animated: true)
    }

    private func setHovered(_ hovered: Bool, animated: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        onHoverChanged(hovered, animated)
    }

    override func updateLayer() {
        super.updateLayer()
        onPressChanged(isEnabled && isHighlighted && !wasTrackingCancelled, isTrackingMouse)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !isHiddenOrHasHiddenAncestor else { return }
        clickVariant = OverlayActionPresentation.variant(for: event.modifierFlags)
        guard !requiresDwell(clickVariant) || dwellProgress >= 1 else { return }
        isTrackingMouse = true
        wasTrackingCancelled = false
        onPressChanged(true, false)
        didFireLongPress = false
        defer {
            cancelLongPress()
            onPressChanged(false, true)
            isTrackingMouse = false
            clickVariant = .left
            didFireLongPress = false
            wasTrackingCancelled = false
        }
        if clickVariant == .left, hasLongPressAction() {
            let timer = Timer(
                timeInterval: TrafficLightInterceptor.longPressThreshold, repeats: false
            ) { [weak self] timer in
                guard let self, longPressTimer === timer else { return }
                longPressTimer = nil
                guard isTrackingMouse, !wasTrackingCancelled, isEnabled,
                      !isHiddenOrHasHiddenAncestor, isHighlighted,
                      let window, window.isVisible, hasLongPressAction() else { return }
                let location = convert(pointerLocationInWindow(window), from: nil)
                guard bounds.contains(location) else { return }
                didFireLongPress = true
                guard !requiresDwell(.longPressLeft) || dwellProgress >= 1 else { return }
                onLongPress()
            }
            longPressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        // Native tracking cancels a short click released outside the control.
        super.mouseDown(with: event)
    }

    fileprivate func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func cancelTracking() {
        guard isTrackingMouse else { return }
        wasTrackingCancelled = true
        cancelLongPress()
        onPressChanged(false, false)
    }

    override func rightMouseDown(with _: NSEvent) {
        guard isEnabled, !requiresDwell(.right) || dwellProgress >= 1 else { return }
        onPressChanged(true, false)
        onActivate(.right)
        onPressChanged(false, true)
    }

    @objc private func activateButton() {
        // Mouse dwell is checked before native tracking begins; keyboard
        // and accessibility activation do not require pointer dwelling.
        guard isEnabled, !isHiddenOrHasHiddenAncestor,
              !didFireLongPress, !wasTrackingCancelled else { return }
        if isTrackingMouse, window?.isVisible != true {
            return
        }
        onActivate(clickVariant)
    }
}

/// Observe AppKit's input tracking, not rendering: an out-and-back drag
/// can happen before the next layer update. AppKit still owns the mouse loop,
/// highlight state, drag reentry, and action delivery.
private final class HoverOverlayButtonCell: NSButtonCell {
    override func startTracking(at _: NSPoint, in _: NSView) -> Bool {
        true
    }

    override func continueTracking(last _: NSPoint, current _: NSPoint, in _: NSView) -> Bool {
        true
    }

    override func stopTracking(
        last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp: Bool
    ) {
        if !mouseIsUp {
            (controlView as? HoverOverlayButtonView)?.cancelLongPress()
        }
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: mouseIsUp)
    }
}

/// Never override NSButton.draw: that opts its subclass out of AppKit's
/// native layer updates, so the Liquid Glass bezel disappears.
private final class HoverDwellIndicatorView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draw(_: NSRect) {
        guard progress > 0, progress < 1 else { return }
        OverlayChipDrawing.drawProgressRing(
            around: bounds.insetBy(dx: 3, dy: 3), progress: progress
        )
    }
}
