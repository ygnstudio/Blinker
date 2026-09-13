import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Shows enlarged traffic-light buttons while the cursor hovers a window's
/// title bar and performs the mapped (or native) action when an enlarged
/// button is clicked.
///
/// Mouse tracking uses a listen-only `CGEventTap` parked on a dedicated
/// thread's run loop, so callbacks never run on (or block) the main thread.
/// AX work happens on a serial work queue; panel updates hop to the main
/// thread. A dwell gate (progress ring fill) protects against accidental
/// clicks.
///
/// The implementation is split across extensions in the same module:
/// `HoverOverlayController+Detection.swift` (work-queue detection) and
/// `HoverOverlayController+Panels.swift` (main-thread panels and dwell).
public final class HoverOverlayController {
    let ruleEngine: RuleEngine
    let actionPerformer: WindowActionPerforming
    let settingsStore: HoverOverlaySettingsStore
    let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "hover-overlay")

    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var tapThread: Thread?
    var tapRunLoop: CFRunLoop?
    let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.hover-overlay")

    // Detection state; only touched on `workQueue`.
    var cachedButtons: [OverlayButtonInfo] = []
    var cachedAXWindow: AXUIElement?
    var cachedWindowPID: pid_t = 0
    var cachedWindowBounds: CGRect?
    var isOverlayVisible = false

    // UI state; only touched on the main thread.
    var panels: [HoverOverlayPanel] = []
    var panelSignature: [CGRect] = []
    var panelPID: pid_t = 0
    var maskPanel: HoverOverlayMaskPanel?
    var hoveredPanel: HoverOverlayPanel?
    var dwellTimer: Timer?
    var dwellStartedAt: Date?
    var activeDwellMilliseconds = 0
    var workspaceObserver: NSObjectProtocol?

    public init(
        ruleEngine: RuleEngine,
        actionPerformer: WindowActionPerforming,
        settingsStore: HoverOverlaySettingsStore
    ) {
        self.ruleEngine = ruleEngine
        self.actionPerformer = actionPerformer
        self.settingsStore = settingsStore
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    /// Installs the listen-only mouse-move tap. Returns `false` when the
    /// Accessibility permission is missing (AX reads would fail anyway).
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AccessibilityPermission.isTrusted else {
            logger.error("start aborted: accessibility permission missing")
            return false
        }
        observeWorkspaceActivation()

        let thread = OverlayTapThread { [weak self] in
            guard let self, !Thread.current.isCancelled else { return }
            let runLoop = RunLoop.current.getCFRunLoop()
            tapRunLoop = runLoop
            installTap(on: runLoop)
        }
        thread.name = "com.ygnstudio.blinker.hover-overlay-tap"
        thread.start()
        tapThread = thread
        logger.info("hover overlay controller started")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }
        tapThread?.cancel()
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
        logger.info("hover overlay controller stopped")
    }

    deinit {
        stop()
    }

    /// Applies new settings and discards visible panels so the next hover
    /// re-renders with the updated configuration. Call from the main thread.
    public func updateConfiguration(_ settings: HoverOverlaySettings) {
        settingsStore.update(settings)
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
        workQueue.async { [weak self] in
            self?.resetDetectionAndHide()
        }
    }

    // MARK: - Screen container

    /// Keep enlarged panels this far away from the screen edges.
    static let screenEdgeMargin: CGFloat = 4

    /// The screen (in AX top-left coordinates) containing the center of the
    /// given button frames, intersected with the window's own bounds and inset
    /// by the edge margin. Clamping to the window keeps the enlarged group
    /// inside windowed windows; intersecting with the screen additionally
    /// covers edge-anchored (fullscreen, tiled) windows.
    static func overlayContainerBounds(
        forButtonFrames buttonFrames: [CGRect],
        windowBounds: CGRect
    ) -> CGRect? {
        guard let groupBounds = HoverOverlayGeometry.unionedBounds(of: buttonFrames) else {
            return nil
        }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return windowBounds }
        let globalMaxY = screens.map(\.frame.maxY).max() ?? 0
        let axFrame: (NSScreen) -> CGRect = { screen in
            CGRect(
                x: screen.frame.minX,
                y: globalMaxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
        let center = CGPoint(x: groupBounds.midX, y: groupBounds.midY)
        let screen = screens.first { axFrame($0).contains(center) } ?? screens[0]
        let container = axFrame(screen).intersection(windowBounds)
        return container.isNull
            ? axFrame(screen).insetBy(dx: screenEdgeMargin, dy: screenEdgeMargin)
            : container.insetBy(dx: screenEdgeMargin, dy: screenEdgeMargin)
    }

    // MARK: - Tap installation

    private func installTap(on runLoop: CFRunLoop) {
        let callback: CGEventTapCallBack = { _, eventType, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<HoverOverlayController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            controller.handleTapEvent(eventType: eventType, event: event)
            return Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(
            1 << CGEventType.mouseMoved.rawValue | 1 << CGEventType.leftMouseDragged.rawValue
        )
        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            logger.error("CGEvent.tapCreate returned nil (listen-only mouse-move tap)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        logger.info("listen-only mouse-move tap installed")
    }

    private func handleTapEvent(eventType: CGEventType, event: CGEvent) {
        switch eventType {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            logger.warning("tap disabled (\(eventType.rawValue)); re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .mouseMoved, .leftMouseDragged:
            let location = event.location
            workQueue.async { [weak self] in
                self?.handleCursorMove(to: location)
            }
        default:
            break
        }
    }
}

/// Dedicated thread hosting the listen-only tap's run loop, so mouse-move
/// callbacks never run on (or block) the main thread.
final class OverlayTapThread: Thread {
    private let configure: () -> Void

    init(configure: @escaping () -> Void) {
        self.configure = configure
    }

    override func main() {
        let runLoop = RunLoop.current
        runLoop.add(Port(), forMode: .default)
        configure()
        while !isCancelled {
            _ = runLoop.run(mode: .default, before: .distantFuture)
        }
    }
}
