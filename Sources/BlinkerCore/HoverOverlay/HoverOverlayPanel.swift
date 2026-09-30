import AppKit

struct OverlayButtonInfo {
    let button: TrafficButton
    let axSubrole: String
    let frame: CGRect
}

/// AppKit owns button drawing, accessibility and press/release tracking.
/// The subclass adds only dwell gating and configurable click variants.
final class HoverOverlayButtonView: NSButton, OverlayDwellPanel {
    private let hasLongPressAction: () -> Bool
    private let onActivate: (ClickVariant) -> Void
    private let onLongPress: () -> Void
    private var dwellProgress: Double = 0
    private let dwellIndicator = HoverDwellIndicatorView()
    private var clickVariant: ClickVariant = .left
    private var didFireLongPress = false
    private var longPressTimer: Timer?

    init(
        frame: NSRect,
        symbol: String,
        label: String,
        color: NSColor,
        hasLongPressAction: @escaping () -> Bool = { false },
        onActivate: @escaping (ClickVariant) -> Void,
        onLongPress: @escaping () -> Void = {}
    ) {
        self.hasLongPressAction = hasLongPressAction
        self.onActivate = onActivate
        self.onLongPress = onLongPress
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

    func setDwellProgress(_ progress: Double) {
        let value = min(max(progress, 0), 1)
        guard dwellProgress != value else { return }
        dwellProgress = value
        dwellIndicator.progress = value
    }

    func resetDwell() {
        setDwellProgress(0)
    }

    override func mouseDown(with event: NSEvent) {
        guard dwellProgress >= 1 else { return }
        clickVariant = event.modifierFlags.contains(.option) ? .optionLeft
            : event.modifierFlags.contains(.function) ? .globeLeft : .left
        didFireLongPress = false
        if clickVariant == .left, hasLongPressAction() {
            let timer = Timer(
                timeInterval: TrafficLightInterceptor.longPressThreshold, repeats: false
            ) { [weak self] _ in
                guard let self, let window, window.isVisible else { return }
                let location = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                guard bounds.contains(location) else { return }
                didFireLongPress = true
                onLongPress()
            }
            longPressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        // Native tracking cancels a short click released outside the control.
        super.mouseDown(with: event)
        longPressTimer?.invalidate()
        longPressTimer = nil
        clickVariant = .left
        didFireLongPress = false
    }

    override func rightMouseDown(with _: NSEvent) {
        guard dwellProgress >= 1 else { return }
        onActivate(.right)
    }

    @objc private func activateButton() {
        // Mouse dwell is checked before native tracking begins; keyboard
        // and accessibility activation do not require pointer dwelling.
        guard !didFireLongPress else { return }
        onActivate(clickVariant)
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
