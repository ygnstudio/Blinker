import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Intercepts mouse clicks on traffic light buttons of other applications and
/// remaps them according to the active rules.
///
/// Pipeline for every left or right mouse down:
/// 1. Locate the on-screen window under the cursor (cheap `CGWindowList` probe)
///    and discard the click early when its title bar region is not involved.
/// 2. Hit-test the exact AX element under the cursor and read its subrole to
///    identify close / minimize / zoom buttons.
/// 3. Derive the click variant (plain, right, ⌥/🌐 modifier click) and ask the
///    `RuleEngine` what to do; `nil` means pass the event through.
/// 4. Otherwise swallow the event, resolve the clicked AX window and delegate
///    the action to the `WindowActionPerformer`.
///
/// Long presses: when the clicked button has a long-press action configured,
/// the mouse down is swallowed but *not* acted on immediately. If the button
/// is released before `longPressThreshold`, the plain left-click action runs;
/// otherwise the long-press action fires while the button is still held. The
/// matching mouse up is always swallowed so the target app never sees a
/// half-forwarded click.
public final class TrafficLightInterceptor {
    private let ruleEngine: RuleEngine
    private let actionPerformer: WindowActionPerforming
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Hosts the event tap's run loop so the callback — including its
    /// synchronous AX hit test — never runs on (or blocks) the main thread.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.interceptor")
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "interceptor")

    /// How long a left click must be held to count as a long press.
    static let longPressThreshold: TimeInterval = 0.45

    private static let titleBarBandHeight: CGFloat = 32

    /// Guards `pendingPress` and `longPressWorkItem`, which are written from
    /// the event tap (main run loop) and the timer (work queue).
    private let pendingLock = NSLock()
    private var pendingPress: PendingPress?
    private var longPressWorkItem: DispatchWorkItem?

    /// A left mouse down waiting to become either a plain click or a long
    /// press. `shortAction` is the plain left-click mapping (`nil` keeps the
    /// button dead for quick clicks); `longAction` fires on timeout.
    private struct PendingPress {
        let windowHit: AXQuery.WindowHit
        let button: TrafficButton
        let shortAction: ButtonAction?
        let longAction: ButtonAction
        var didFireLong = false
    }

    public init(ruleEngine: RuleEngine, actionPerformer: WindowActionPerforming) {
        self.ruleEngine = ruleEngine
        self.actionPerformer = actionPerformer
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    /// Installs the event tap. Returns `false` when the Accessibility
    /// permission is missing or the system refuses the tap.
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AccessibilityPermission.isTrusted else {
            logger.error("start aborted: accessibility permission missing")
            return false
        }

        let callback: CGEventTapCallBack = { _, eventType, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<TrafficLightInterceptor>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return interceptor.handle(event: event, eventType: eventType)
        }

        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
        )

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            logger.error("CGEvent.tapCreate returned nil (hidTap, headInsert, defaultTap)")
            return false
        }

        // The tap is created here (so failures report synchronously) but
        // hosted on a dedicated thread: its callback performs synchronous AX
        // IPC with a 250 ms timeout, which must never stall the main thread.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = OverlayTapThread { [weak self] in
            guard let self, !Thread.current.isCancelled else { return }
            let runLoop = RunLoop.current.getCFRunLoop()
            self.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        thread.name = "com.ygnstudio.blinker.interceptor-tap"
        thread.start()

        tapThread = thread
        eventTap = tap
        runLoopSource = source
        logger.info("event tap installed on dedicated thread")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
        }
        tapThread?.cancel()
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
    }

    deinit {
        stop()
    }

    // MARK: - Event handling

    private func handle(event: CGEvent, eventType: CGEventType) -> Unmanaged<CGEvent>? {
        // The system can disable the tap (e.g. after a timeout); re-arm it.
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            logger.warning("tap disabled (\(eventType.rawValue)); re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch eventType {
        case .leftMouseUp:
            return handleLeftMouseUp(event: event)
        case .leftMouseDown, .rightMouseDown:
            return handleMouseDown(event: event, isRightClick: eventType == .rightMouseDown)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Resolves a pending press when the left button is released. The matching
    /// mouse up is always swallowed: the original mouse down never reached the
    /// target app, so forwarding a lone mouse up would be misleading.
    private func handleLeftMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        pendingLock.lock()
        let pending = pendingPress
        pendingPress = nil
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        pendingLock.unlock()

        guard let pending else { return Unmanaged.passUnretained(event) }
        if !pending.didFireLong, let shortAction = pending.shortAction {
            workQueue.async { [weak self] in
                self?.perform(shortAction, button: pending.button, window: pending.windowHit)
            }
        }
        return nil
    }

    private func handleMouseDown(event: CGEvent, isRightClick: Bool) -> Unmanaged<CGEvent>? {
        // A click just consumed by a hover overlay panel must not be
        // re-interpreted here (the tap fires before window routing).
        guard !OverlayClickGate.isSuppressed else {
            logger.debug("click suppressed (consumed by overlay panel); pass-through")
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        guard let window = AXQuery.windowUnderPoint(location) else { return Unmanaged.passUnretained(event) }
        guard
            let decision = resolveDecision(
                location: location,
                window: window,
                isRightClick: isRightClick,
                flags: event.flags
            )
        else {
            return Unmanaged.passUnretained(event)
        }

        // Swallow the original click.
        if let pending = makePendingPress(decision: decision, windowHit: window) {
            scheduleLongPress(pending)
        } else {
            workQueue.async { [weak self] in
                self?.perform(decision.action, button: decision.button, window: window)
            }
        }
        return nil
    }

    // MARK: - Long-press scheduling

    private func makePendingPress(
        decision: Decision,
        windowHit: AXQuery.WindowHit
    ) -> PendingPress? {
        guard let longAction = decision.longPressAction else { return nil }
        return PendingPress(
            windowHit: windowHit,
            button: decision.button,
            shortAction: decision.action,
            longAction: longAction
        )
    }

    private func scheduleLongPress(_ pending: PendingPress) {
        pendingLock.lock()
        pendingPress = pending
        let workItem = DispatchWorkItem { [weak self] in
            self?.fireLongPressIfNeeded()
        }
        longPressWorkItem = workItem
        pendingLock.unlock()

        workQueue.asyncAfter(deadline: .now() + Self.longPressThreshold, execute: workItem)
    }

    /// Runs on the work queue when the long-press deadline elapses.
    private func fireLongPressIfNeeded() {
        pendingLock.lock()
        guard let pending = pendingPress, !pending.didFireLong else {
            pendingLock.unlock()
            return
        }
        pendingPress?.didFireLong = true
        let longAction = pending.longAction
        let windowHit = pending.windowHit
        pendingLock.unlock()

        logger.info("long press threshold reached; firing long-press action")
        perform(longAction, button: pending.button, window: windowHit)
    }

    // MARK: - Action execution

    private func perform(_ action: ButtonAction, button: TrafficButton, window hit: AXQuery.WindowHit) {
        // Resolve the AX window that was actually clicked. The swallowed
        // mouse-down never activates the app, so the focused window can be a
        // different one; matching by frame keeps the action on the right
        // window when several windows of the same app are open.
        guard
            let targetWindow = AXQuery.resolveWindow(
                processIdentifier: hit.processIdentifier,
                bounds: hit.bounds
            )
        else {
            logger.warning("no AX window matched the clicked CG window")
            return
        }
        actionPerformer.perform(
            action,
            button: button,
            window: targetWindow,
            processIdentifier: hit.processIdentifier
        )
    }

    // MARK: - AX hit test

    /// Identifies the traffic button under the cursor via an AX hit test.
    private static func trafficButton(
        at point: CGPoint,
        expectedProcessIdentifier processIdentifier: pid_t
    ) -> TrafficButton? {
        let systemWide = AXUIElementCreateSystemWide()
        AXQuery.applyMessagingTimeout(systemWide)
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == processIdentifier else { return nil }

        guard let subrole = AXQuery.stringAttribute(element, kAXSubroleAttribute) else { return nil }
        return TrafficButton(axSubrole: subrole)
    }
}

// MARK: - Decision

extension TrafficLightInterceptor {
    /// What to do with a click on a traffic button.
    fileprivate struct Decision {
        let action: ButtonAction
        /// The traffic button that was clicked; forwarded to the performer.
        let button: TrafficButton
        /// When set, the click enters long-press mode instead of executing
        /// `action` right away (plain left click with a long-press mapping).
        let longPressAction: ButtonAction?
    }

    /// Resolves whether the click should be intercepted and with which action.
    /// Logs every rejection reason; returns `nil` for pass-through.
    fileprivate func resolveDecision(
        location: CGPoint,
        window: AXQuery.WindowHit,
        isRightClick: Bool,
        flags: CGEventFlags
    ) -> Decision? {
        // Coarse rejection: only clicks inside the title bar band reach the
        // (comparatively expensive) AX hit test.
        guard location.y - window.bounds.minY <= Self.titleBarBandHeight else {
            logger.debug("click outside title bar band; pass-through")
            return nil
        }

        guard
            let app = NSRunningApplication(processIdentifier: window.processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else {
            logger.debug("no running app/bundle id for pid \(window.processIdentifier)")
            return nil
        }

        // Cheap second rejection: no rule for this app at all.
        guard ruleEngine.hasRule(forBundleIdentifier: bundleIdentifier) else {
            logger.debug("\(bundleIdentifier, privacy: .public): no rule; pass-through")
            return nil
        }

        guard
            let button = Self.trafficButton(
                at: location,
                expectedProcessIdentifier: window.processIdentifier
            )
        else {
            logger.debug("\(bundleIdentifier, privacy: .public): AX found no traffic button")
            return nil
        }

        let variant = Self.clickVariant(isRightClick: isRightClick, flags: flags)
        guard let action = configuredAction(
            bundleIdentifier: bundleIdentifier,
            button: button,
            variant: variant
        ) else {
            return nil
        }

        // A plain left click on a button that also has a long-press mapping
        // waits for release/timeout instead of executing immediately.
        var longPressAction: ButtonAction?
        if variant == .left {
            if let configured = ruleEngine.action(
                forBundleIdentifier: bundleIdentifier,
                button: button,
                variant: .longPressLeft
            ) {
                longPressAction = configured
            }
        }

        let buttonName = String(describing: button)
        let actionName = String(describing: action)
        let summary = "\(buttonName)/\(String(describing: variant)) -> \(actionName)"
        logger.info("\(bundleIdentifier, privacy: .public): \(summary, privacy: .public)")
        return Decision(action: action, button: button, longPressAction: longPressAction)
    }

    /// Maps a physical click to its configured variant. Modifier checks come
    /// first (⌥ then 🌐); a plain left click may become a long-press pending.
    fileprivate static func clickVariant(isRightClick: Bool, flags: CGEventFlags) -> ClickVariant {
        if isRightClick {
            return .right
        }
        if flags.contains(.maskAlternate) {
            return .optionLeft
        }
        if flags.contains(.maskSecondaryFn) {
            return .globeLeft
        }
        return .left
    }

    /// Looks up the mapped action for a click, logging pass-through decisions.
    private func configuredAction(
        bundleIdentifier: String,
        button: TrafficButton,
        variant: ClickVariant
    ) -> ButtonAction? {
        guard let action = ruleEngine.action(
            forBundleIdentifier: bundleIdentifier,
            button: button,
            variant: variant
        ) else {
            let variantName = String(describing: variant)
            let reason = "\(button.axSubrole) \(variantName) maps to nil"
            logger.debug("\(bundleIdentifier, privacy: .public): \(reason, privacy: .public)")
            return nil
        }
        return action
    }
}
