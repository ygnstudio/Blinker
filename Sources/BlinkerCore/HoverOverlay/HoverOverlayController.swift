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
/// The implementation is split across focused collaborators and extensions
/// in the same module: `OverlayHUDManager` (management HUD), `OverlayDwellController`
/// (dwell gate), `HoverOverlayController+Detection.swift` (work-queue
/// detection) and `HoverOverlayController+Panels.swift` (main-thread panels).
public final class HoverOverlayController {
    let ruleEngine: RuleEngine
    let actionPerformer: WindowActionPerforming
    let settingsStore: HoverOverlaySettingsStore
    /// Snapshot of saved workspaces for the management HUD, taken when the
    /// HUD opens.
    let workspacesProvider: () -> [HUDWorkspaceItem]
    /// Restores a workspace; wired to the app's `WorkspaceStore`.
    let workspaceRestorer: (UUID) -> Void
    let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "hover-overlay")

    /// Hosts the listen-only mouse-move tap on a dedicated thread, so
    /// callbacks never run on (or block) the main thread. `stop()` waits for
    /// the thread's exit, making the unretained `userInfo` pointer safe.
    let tapHost = EventTapThreadHost(threadName: "hover-overlay-tap")
    let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.hover-overlay")

    // Detection state; only touched on `workQueue`.
    var cachedButtons: [OverlayButtonInfo] = []
    var cachedAXWindow: AXUIElement?
    var cachedWindowPID: pid_t = 0
    /// The CG window id of the cached hit; same-pid-same-frame window swaps
    /// (close + reopen at the same spot) are caught by comparing it.
    var cachedWindowID: CGWindowID = 0
    var cachedWindowBounds: CGRect?
    var wakeGate = OverlayWakeGate()
    var wakeCheckScheduled = false
    var wakeCheckRevision: UInt64 = 0

    /// UI state; only touched on the main thread.
    var panels: [HoverOverlayButtonView] = []
    /// Extra action chips appended after `panels`; the combined array order
    /// matches `OverlayLayout.allPanelFrames`.
    var extraPanels: [HoverOverlayButtonView] = []
    var panelWindowID: CGWindowID = 0
    var panelSignature: [CGRect] = []
    var panelPID: pid_t = 0
    /// One glass panel hosts all visible controls in the same view hierarchy.
    var trayPanel: HoverOverlayTrayPanel?
    /// The extra actions the current chips were built with; a change also
    /// triggers a rebuild.
    var panelExtraActions: [ButtonAction] = []
    var workspaceObserver: NSObjectProtocol?
    /// The management HUD (open/close/keep-alive geometry).
    let hud: OverlayHUDManager
    /// Dwell tracking for the displayed chips (main-thread only).
    let dwell = OverlayDwellController()
    let presentationState = OverlayPresentationState()

    public init(
        ruleEngine: RuleEngine,
        actionPerformer: WindowActionPerforming,
        settingsStore: HoverOverlaySettingsStore,
        workspacesProvider: @escaping () -> [HUDWorkspaceItem] = { [] },
        workspaceRestorer: @escaping (UUID) -> Void = { _ in }
    ) {
        self.ruleEngine = ruleEngine
        self.actionPerformer = actionPerformer
        self.settingsStore = settingsStore
        self.workspacesProvider = workspacesProvider
        self.workspaceRestorer = workspaceRestorer
        hud = OverlayHUDManager(
            workspacesProvider: workspacesProvider,
            workspaceRestorer: workspaceRestorer,
            actionPerformer: actionPerformer,
            workQueue: workQueue,
            logger: logger
        )
    }

    public var isRunning: Bool {
        tapHost.isRunning
    }

    /// Installs the listen-only mouse-move tap. Returns `false` when the
    /// Accessibility permission is missing (AX reads would fail anyway).
    @discardableResult
    public func start() -> Bool {
        guard !tapHost.isRunning else { return true }
        guard AccessibilityPermission.isTrusted else {
            logger.error("start aborted: accessibility permission missing")
            return false
        }
        observeWorkspaceActivation()

        let callback: CGEventTapCallBack = { _, eventType, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<HoverOverlayController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            controller.handleTapEvent(eventType: eventType, event: event)
            return Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(
            (1 << CGEventType.mouseMoved.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
        )
        guard
            tapHost.start(
                mask: mask,
                options: .listenOnly,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }
        logger.info("hover overlay controller started")
        return true
    }

    public func stop() {
        tapHost.stop()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
        logger.info("hover overlay controller stopped")
    }

    /// Any app activation change hides the overlay; the next mouse move
    /// re-creates it when still hovering a title bar. Activation can also
    /// reorder windows under a stationary cursor, so the window-hit cache
    /// is dropped as well.
    private func observeWorkspaceActivation() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AXQuery.invalidateWindowUnderPointCache()
            self?.hidePanels()
        }
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
    /// given button frames, intersected with the target window and inset to
    /// keep the tray away from both window and display edges.
    static func overlayContainerBounds(
        forButtonFrames buttonFrames: [CGRect],
        windowBounds: CGRect
    ) -> CGRect? {
        guard let groupBounds = HoverOverlayGeometry.unionedBounds(of: buttonFrames) else {
            return nil
        }
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return windowBounds.insetBy(dx: screenEdgeMargin, dy: screenEdgeMargin)
        }
        let globalMaxY = AXQuery.coordinatePivotY
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
        guard !container.isNull, container.width > 2 * screenEdgeMargin,
              container.height > 2 * screenEdgeMargin else { return nil }
        return container.insetBy(dx: screenEdgeMargin, dy: screenEdgeMargin)
    }

    // MARK: - Tap events

    /// Left-button drag lifecycle plus latest-wins coalescing for cursor
    /// detection. The tap callback runs on the tap thread and detection on
    /// `workQueue`; both touch these fields through `moveStateLock`.
    private let moveStateLock = NSLock()
    private var isDragging = false
    private var isMouseButtonDown = false

    var canDetectCursor: Bool {
        moveStateLock.withLock { !isDragging && !isMouseButtonDown }
    }

    private var isDetecting = false
    private var pendingMoveLocation: CGPoint?

    private func handleTapEvent(eventType: CGEventType, event: CGEvent) {
        switch eventType {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            logger.warning("tap disabled (\(eventType.rawValue)); re-enabling")
            tapHost.enableTap()
        case .leftMouseDown:
            moveStateLock.lock()
            isMouseButtonDown = true
            isDragging = false
            moveStateLock.unlock()
        case .leftMouseUp:
            moveStateLock.lock()
            isMouseButtonDown = false
            isDragging = false
            moveStateLock.unlock()
        case .leftMouseDragged:
            moveStateLock.lock()
            let startedDragging = !isDragging
            isDragging = true
            moveStateLock.unlock()
            // While a window drags, its bounds change with every event, so
            // cursor detection would re-resolve AX frames and rebuild the
            // panels at drag frequency — pure churn that stutters the drag
            // itself. Stand down once and wait for the mouse up. The drag
            // also reorders windows, so the window-hit cache must go too.
            if startedDragging {
                AXQuery.invalidateWindowUnderPointCache()
                DispatchQueue.main.async { [weak self] in
                    self?.hidePanels()
                }
            }
        case .mouseMoved, .flagsChanged:
            scheduleCursorMove(event.location)
        default:
            break
        }
    }

    /// Enqueues one cursor move for detection, dropping intermediate events
    /// while a detection pass is already running (latest-wins): mouse moves
    /// arrive faster than AX work can complete, and a serial queue would
    /// otherwise accumulate backlog that lags the overlay behind the cursor.
    private func scheduleCursorMove(_ location: CGPoint) {
        moveStateLock.lock()
        if isDragging {
            moveStateLock.unlock()
            return
        }
        if isDetecting {
            pendingMoveLocation = location
            moveStateLock.unlock()
            return
        }
        isDetecting = true
        moveStateLock.unlock()
        workQueue.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            self?.drainCursorMoves(from: location)
        }
    }

    /// One detection per frame at most. Keep the detecting flag set while
    /// AX work runs so new input replaces the pending point, not the queue.
    private func drainCursorMoves(from location: CGPoint) {
        moveStateLock.lock()
        if isDragging || !tapHost.isRunning {
            pendingMoveLocation = nil
            isDetecting = false
            moveStateLock.unlock()
            return
        }
        let current = pendingMoveLocation ?? location
        pendingMoveLocation = nil
        moveStateLock.unlock()
        handleCursorMove(to: current)

        moveStateLock.lock()
        let pending = pendingMoveLocation
        if pending == nil {
            isDetecting = false
        }
        moveStateLock.unlock()
        if let pending {
            workQueue.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
                self?.drainCursorMoves(from: pending)
            }
        }
    }
}
