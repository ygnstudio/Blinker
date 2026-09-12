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
public final class HoverOverlayController {
    private let ruleEngine: RuleEngine
    private let actionPerformer: WindowActionPerforming
    private let settingsStore: HoverOverlaySettingsStore
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "hover-overlay")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.hover-overlay")

    // Detection state; only touched on `workQueue`.
    private var cachedButtons: [OverlayButtonInfo] = []
    private var cachedAXWindow: AXUIElement?
    private var cachedWindowPID: pid_t = 0
    private var cachedWindowBounds: CGRect?
    private var lastHoveredIndex: Int?
    private var isOverlayVisible = false

    // UI state; only touched on the main thread.
    private var panels: [HoverOverlayPanel] = []
    private var panelSignature: [CGRect] = []
    private var panelPID: pid_t = 0
    private var hoveredPanel: HoverOverlayPanel?
    private var dwellTimer: Timer?
    private var dwellStartedAt: Date?
    private var activeDwellMilliseconds = 0
    private var workspaceObserver: NSObjectProtocol?

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

    // MARK: - Cursor tracking (work queue)

    private func handleCursorMove(to location: CGPoint) {
        let settings = settingsStore.snapshot
        guard settings.isEnabled, let target = allowedTarget(at: location, settings: settings) else {
            resetDetectionAndHide()
            return
        }

        let resolved = resolveButtons(windowHit: target.hit)
        guard !resolved.buttons.isEmpty, let axWindow = resolved.axWindow else {
            resetDetectionAndHide()
            return
        }

        let hoveredIndex = hoveredPanelIndex(
            cursor: location,
            buttons: resolved.buttons,
            enlargedSize: settings.enlargedSize
        )
        syncPanels(
            buttons: resolved.buttons,
            axWindow: axWindow,
            target: target,
            hoveredIndex: hoveredIndex,
            settings: settings
        )
    }

    /// Cheap pass/fail checks before any AX work: window under cursor, title
    /// bar band, and (when `appliesToAllWindows` is off) rule existence.
    private func allowedTarget(
        at location: CGPoint,
        settings: HoverOverlaySettings
    ) -> (hit: AXQuery.WindowHit, bundleIdentifier: String, appName: String?)? {
        guard
            let hit = AXQuery.windowUnderPoint(
                location,
                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            HoverOverlayGeometry.isCursorInTitleBarBand(cursor: location, windowBounds: hit.bounds),
            let app = NSRunningApplication(processIdentifier: hit.processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else { return nil }
        if !settings.appliesToAllWindows, !ruleEngine.hasRule(forBundleIdentifier: bundleIdentifier) {
            return nil
        }
        return (hit, bundleIdentifier, app.localizedName)
    }

    /// Returns the traffic buttons of the window under the cursor, re-reading
    /// them via AX only when the CG window bounds changed (or the cache is
    /// empty); otherwise serves the cached values.
    private func resolveButtons(
        windowHit: AXQuery.WindowHit
    ) -> (buttons: [OverlayButtonInfo], axWindow: AXUIElement?) {
        if cachedWindowPID == windowHit.processIdentifier,
           !HoverOverlayGeometry.hasWindowBoundsChanged(
               previous: cachedWindowBounds,
               current: windowHit.bounds
           )
        {
            return (cachedButtons, cachedAXWindow)
        }

        guard
            let axWindow = AXQuery.resolveWindow(
                processIdentifier: windowHit.processIdentifier,
                bounds: windowHit.bounds
            )
        else {
            cacheButtons([], axWindow: nil, hit: windowHit)
            return ([], nil)
        }
        let buttons = Self.readTrafficButtons(in: axWindow)
        cacheButtons(buttons, axWindow: axWindow, hit: windowHit)
        return (buttons, axWindow)
    }

    private func cacheButtons(_ buttons: [OverlayButtonInfo], axWindow: AXUIElement?,
                              hit: AXQuery.WindowHit)
    {
        cachedButtons = buttons
        cachedAXWindow = axWindow
        cachedWindowPID = hit.processIdentifier
        cachedWindowBounds = hit.bounds
    }

    private func resetDetectionAndHide() {
        cachedButtons = []
        cachedAXWindow = nil
        cachedWindowPID = 0
        cachedWindowBounds = nil
        guard isOverlayVisible else { return }
        isOverlayVisible = false
        lastHoveredIndex = nil
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    /// Reads the standard traffic-light buttons of a window via AX, ordered
    /// left to right.
    private static func readTrafficButtons(in window: AXUIElement) -> [OverlayButtonInfo] {
        AXQuery.applyMessagingTimeout(window)
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
            let children = childrenRef as? [AXUIElement]
        else { return [] }

        var buttons: [OverlayButtonInfo] = []
        for child in children {
            AXQuery.applyMessagingTimeout(child)
            guard
                let subrole = AXQuery.stringAttribute(child, kAXSubroleAttribute),
                let button = TrafficButton(axSubrole: subrole),
                let frame = AXQuery.elementFrame(child)
            else { continue }
            buttons.append(OverlayButtonInfo(button: button, axSubrole: subrole, frame: frame))
        }
        return buttons.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func hoveredPanelIndex(
        cursor: CGPoint,
        buttons: [OverlayButtonInfo],
        enlargedSize: CGFloat
    ) -> Int? {
        buttons.firstIndex { info in
            let panelFrame = HoverOverlayGeometry.panelFrame(
                forButtonFrame: info.frame,
                enlargedSize: enlargedSize
            )
            return HoverOverlayGeometry.isCursorInPanel(cursor: cursor, panelFrame: panelFrame)
        }
    }

    // MARK: - Panels (main thread)

    private func syncPanels(
        buttons: [OverlayButtonInfo],
        axWindow: AXUIElement,
        target: (hit: AXQuery.WindowHit, bundleIdentifier: String, appName: String?),
        hoveredIndex: Int?,
        settings: HoverOverlaySettings
    ) {
        let signature = buttons.map(\.frame)
        let pid = target.hit.processIdentifier
        lastHoveredIndex = hoveredIndex
        isOverlayVisible = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if signature != panelSignature || pid != panelPID || panels.count != buttons.count {
                rebuildPanels(
                    buttons: buttons,
                    axWindow: axWindow,
                    processIdentifier: pid,
                    bundleIdentifier: target.bundleIdentifier,
                    appName: target.appName,
                    enlargedSize: settings.enlargedSize
                )
            } else {
                panels.forEach { $0.orderFrontRegardless() }
            }
            applyHoverTransition(hoveredIndex: hoveredIndex, dwellMilliseconds: settings.dwellMilliseconds)
        }
    }

    private func rebuildPanels(
        buttons: [OverlayButtonInfo],
        axWindow: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String,
        appName: String?,
        enlargedSize: CGFloat
    ) {
        hidePanels()
        panels = buttons.map { info in
            let title = previewTitle(
                button: info.button,
                bundleIdentifier: bundleIdentifier,
                appName: appName
            )
            return HoverOverlayPanel(
                buttonFrame: info.frame,
                info: info,
                title: title,
                enlargedSize: enlargedSize
            ) { [weak self] in
                self?.activate(
                    info: info,
                    axWindow: axWindow,
                    processIdentifier: processIdentifier,
                    bundleIdentifier: bundleIdentifier
                )
            }
        }
        panelSignature = buttons.map(\.frame)
        panelPID = processIdentifier
        panels.forEach { $0.orderFrontRegardless() }
    }

    private func hidePanels() {
        stopDwell()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        panelSignature = []
        panelPID = 0
    }

    /// Performs the rule action (or a native AXPress when no rule applies)
    /// and hides the overlay. Runs on the main thread.
    private func activate(
        info: OverlayButtonInfo,
        axWindow: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String?
    ) {
        logger.info("overlay button activated: \(info.axSubrole, privacy: .public)")
        if let action = bundleIdentifier.flatMap({ ruleEngine.action(
            forBundleIdentifier: $0,
            button: info.button
        ) }) {
            workQueue.async { [actionPerformer] in
                actionPerformer.perform(
                    action,
                    button: info.button,
                    window: axWindow,
                    processIdentifier: processIdentifier
                )
            }
        } else {
            workQueue.async { [weak self] in
                // The click was swallowed by the panel; log a failed press so
                // the user's dead click is at least diagnosable.
                if !AXQuery.pressButton(subrole: info.axSubrole, in: axWindow) {
                    self?.logger.error(
                        "native AXPress failed for \(info.axSubrole, privacy: .public); click was consumed"
                    )
                }
            }
        }
        // Deferred so the view survives the ongoing mouseDown dispatch.
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    // MARK: - Dwell (main thread)

    /// Applies a hover transition: resets the previous panel's dwell and
    /// starts (or skips, when dwell is 0 ms) dwell on the newly hovered one.
    private func applyHoverTransition(hoveredIndex: Int?, dwellMilliseconds: Int) {
        guard let index = hoveredIndex, panels.indices.contains(index) else {
            stopDwell()
            return
        }
        let panel = panels[index]
        guard panel !== hoveredPanel else { return }
        hoveredPanel?.buttonView.resetDwell()
        hoveredPanel = panel
        activeDwellMilliseconds = dwellMilliseconds
        dwellStartedAt = Date()
        if dwellMilliseconds <= 0 {
            panel.buttonView.setDwellProgress(1)
            stopDwellTimer()
        } else {
            startDwellTimer()
        }
    }

    private func stopDwell() {
        hoveredPanel?.buttonView.resetDwell()
        hoveredPanel = nil
        dwellStartedAt = nil
        stopDwellTimer()
    }

    private func startDwellTimer() {
        stopDwellTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            tickDwell()
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func stopDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    private func tickDwell() {
        guard let panel = hoveredPanel, let start = dwellStartedAt else { return }
        let elapsedMilliseconds = Date().timeIntervalSince(start) * 1000
        let progress = HoverOverlayGeometry.dwellProgress(
            elapsedMilliseconds: elapsedMilliseconds,
            dwellMilliseconds: activeDwellMilliseconds
        )
        panel.buttonView.setDwellProgress(progress)
        if progress >= 1 {
            stopDwellTimer()
        }
    }

    // MARK: - Preview text

    /// Builds the hover preview text, e.g. "退出 Safari". Uses the rule action
    /// when configured, otherwise the native action name.
    private func previewTitle(button: TrafficButton, bundleIdentifier: String, appName: String?) -> String {
        let action = ruleEngine.action(forBundleIdentifier: bundleIdentifier, button: button)
        let verb = action.map(Self.ruleActionName) ?? Self.nativeActionName(button)
        switch action {
        case .quitApp, .hideApp:
            return appName.map { "\(verb) \($0)" } ?? verb
        default:
            return verb
        }
    }

    private static func ruleActionName(_ action: ButtonAction) -> String {
        switch action {
        case .closeWindow: "关闭窗口"
        case .quitApp: "退出"
        case .minimize: "最小化"
        case .hideApp: "隐藏"
        case .maximize: "最大化"
        case .fullscreen: "全屏"
        case .tileLeft: "窗口居左"
        case .tileRight: "窗口居右"
        case .none: "无操作"
        }
    }

    private static func nativeActionName(_ button: TrafficButton) -> String {
        switch button {
        case .close: "关闭窗口"
        case .minimize: "最小化"
        case .zoom: "进入全屏"
        }
    }

    // MARK: - Workspace observation

    /// Any app activation change hides the overlay; the next mouse move
    /// re-creates it when still hovering a title bar.
    private func observeWorkspaceActivation() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanels()
        }
    }
}

/// Dedicated thread hosting the listen-only tap's run loop, so mouse-move
/// callbacks never run on (or block) the main thread.
private final class OverlayTapThread: Thread {
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
