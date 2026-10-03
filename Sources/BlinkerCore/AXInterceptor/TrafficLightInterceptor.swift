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
/// original AX button bounds govern the hold: leaving cancels both actions,
/// even if the pointer returns before release. Drag tracking performs no AX calls.
/// The matching mouse up is always swallowed so the target app never sees a
/// half-forwarded click.
public final class TrafficLightInterceptor {
    private let ruleEngine: RuleEngine
    private let actionPerformer: WindowActionPerforming
    /// Hosts the event tap on a dedicated thread: its callback — including
    /// the synchronous AX hit test — never runs on (or blocks) the main
    /// thread. `stop()` waits for the thread's exit, so the unretained
    /// `userInfo` pointer below is never used after deallocation.
    private let tapHost = EventTapThreadHost(threadName: "interceptor-tap")
    private let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.interceptor")
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "interceptor")

    /// How long a left click must be held to count as a long press.
    static let longPressThreshold: TimeInterval = 0.45

    /// Guards `leftPress`, `longPressWorkItem` and the swallow flag
    /// below, which are written from the event tap and the timer (work
    /// queue).
    private let pendingLock = NSLock()
    private var leftPress = TrafficLightPressState()
    private var longPressWorkItem: DispatchWorkItem?
    /// Whether the previous right mouse *down* was swallowed, so the
    /// matching up is swallowed too — the target app must never see an
    /// orphaned mouse-up for a click that never landed.
    private var didSwallowRightDown = false

    public init(ruleEngine: RuleEngine, actionPerformer: WindowActionPerforming) {
        self.ruleEngine = ruleEngine
        self.actionPerformer = actionPerformer
    }

    public var isRunning: Bool {
        tapHost.isRunning
    }

    /// Installs the event tap. Returns `false` when the Accessibility
    /// permission is missing or the system refuses the tap.
    @discardableResult
    public func start() -> Bool {
        guard !tapHost.isRunning else { return true }
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
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.rightMouseUp.rawValue)
        )

        guard
            tapHost.start(
                mask: mask,
                options: .defaultTap,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }
        logger.info("event tap installed on dedicated thread")
        return true
    }

    public func stop() {
        tapHost.stop()
        // Drop any in-flight long press so a late timer can never fire its
        // action after the interceptor stood down.
        pendingLock.lock()
        leftPress.reset()
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        didSwallowRightDown = false
        pendingLock.unlock()
    }

    deinit {
        stop()
    }

    // MARK: - Event handling

    private func handle(event: CGEvent, eventType: CGEventType) -> Unmanaged<CGEvent>? {
        // The system can disable the tap (e.g. after a timeout); re-arm it.
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            logger.warning("tap disabled (\(eventType.rawValue)); re-enabling")
            tapHost.enableTap()
            return Unmanaged.passUnretained(event)
        }

        switch eventType {
        case .leftMouseUp:
            return handleLeftMouseUp(event: event)
        case .leftMouseDragged:
            return handleLeftMouseDragged(event: event)
        case .rightMouseUp:
            return handleRightMouseUp(event: event)
        case .leftMouseDown, .rightMouseDown:
            return handleMouseDown(event: event, isRightClick: eventType == .rightMouseDown)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Resolves a pending press when the left button is released. The
    /// matching mouse up is always swallowed when its down was: the original
    /// mouse down never reached the target app, so forwarding a lone mouse
    /// up would be misleading.
    private func handleLeftMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        pendingLock.lock()
        let release = leftPress.release(at: event.location)
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        pendingLock.unlock()

        if let invocation = release.invocation {
            workQueue.async { [weak self] in
                self?.perform(invocation.action, window: invocation.windowHit)
            }
        }
        return release.swallowed ? nil : Unmanaged.passUnretained(event)
    }

    private func handleLeftMouseDragged(event: CGEvent) -> Unmanaged<CGEvent>? {
        // The button frame was read once on mouse-down. Never put AX IPC on
        // the high-frequency drag path.
        pendingLock.lock()
        let swallowed = leftPress.drag(to: event.location)
        if leftPress.pending == nil {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
        }
        pendingLock.unlock()
        return swallowed ? nil : Unmanaged.passUnretained(event)
    }

    /// The right-click counterpart of `handleLeftMouseUp`: a right mouse up
    /// is swallowed exactly when its down was (right clicks never enter the
    /// long-press pipeline).
    private func handleRightMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        pendingLock.lock()
        let swallowUp = didSwallowRightDown
        didSwallowRightDown = false
        pendingLock.unlock()
        return swallowUp ? nil : Unmanaged.passUnretained(event)
    }

    private func handleMouseDown(event: CGEvent, isRightClick: Bool) -> Unmanaged<CGEvent>? {
        // A click just consumed by a hover overlay panel must not be
        // re-interpreted here (the tap fires before window routing); only
        // clicks near the consumed one are gated, so a fast second click on
        // another window's traffic lights keeps its remapping.
        guard !OverlayClickGate.isSuppressed(at: event.location) else {
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

        // Swallow the original click — and remember which button, so the
        // matching mouse up is swallowed as well (no orphaned ups).
        if isRightClick {
            pendingLock.lock()
            didSwallowRightDown = true
            pendingLock.unlock()
        } else {
            scheduleLeftPress(makePendingPress(decision: decision, windowHit: window))
        }
        if decision.longPressAction == nil {
            workQueue.async { [weak self] in
                self?.perform(decision.action, window: window)
            }
        }
        return nil
    }

    // MARK: - Long-press scheduling

    private func makePendingPress(
        decision: Decision,
        windowHit: AXQuery.WindowHit
    ) -> TrafficLightPressState.Pending? {
        guard let longAction = decision.longPressAction,
              let bounds = decision.buttonBounds else { return nil }
        return TrafficLightPressState.Pending(
            bounds: bounds,
            windowHit: windowHit,
            shortAction: decision.action,
            longAction: longAction
        )
    }

    private func scheduleLeftPress(_ pending: TrafficLightPressState.Pending?) {
        pendingLock.lock()
        longPressWorkItem?.cancel()
        leftPress.begin(pending)
        let workItem = pending.map { press in
            DispatchWorkItem { [weak self] in
                self?.fireLongPressIfNeeded(id: press.id)
            }
        }
        longPressWorkItem = workItem
        pendingLock.unlock()

        if let workItem {
            workQueue.asyncAfter(deadline: .now() + Self.longPressThreshold, execute: workItem)
        }
    }

    /// Runs on the work queue when the long-press deadline elapses.
    private func fireLongPressIfNeeded(id: UUID) {
        let location = CGEvent(source: nil)?.location
        pendingLock.lock()
        let invocation = leftPress.deadline(for: id, at: location)
        pendingLock.unlock()

        guard let invocation else { return }
        logger.info("long press threshold reached; firing long-press action")
        perform(invocation.action, window: invocation.windowHit)
    }

    // MARK: - Action execution

    private func perform(_ action: ButtonAction, window hit: AXQuery.WindowHit) {
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
            window: targetWindow,
            processIdentifier: hit.processIdentifier
        )
    }

    // MARK: - AX hit test

    /// Identifies the traffic button under the cursor via an AX hit test.
    private static func trafficButton(
        at point: CGPoint,
        expectedProcessIdentifier processIdentifier: pid_t
    ) -> (button: TrafficButton, bounds: CGRect?)? {
        let systemWide = AXUIElementCreateSystemWide()
        AXQuery.applyMessagingTimeout(systemWide)
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == processIdentifier else { return nil }

        AXQuery.applyMessagingTimeout(element)
        guard let subrole = AXQuery.stringAttribute(element, kAXSubroleAttribute),
              let button = TrafficButton(axSubrole: subrole) else { return nil }
        return (button, AXQuery.elementFrame(element))
    }
}

// MARK: - Decision

private extension TrafficLightInterceptor {
    /// What to do with a click on a traffic button.
    struct Decision {
        let action: ButtonAction
        let buttonBounds: CGRect?
        /// When set, the click enters long-press mode instead of executing
        /// `action` right away (plain left click with a long-press mapping).
        let longPressAction: ButtonAction?
    }

    /// Resolves whether the click should be intercepted and with which action.
    /// Logs every rejection reason; returns `nil` for pass-through.
    func resolveDecision(
        location: CGPoint,
        window: AXQuery.WindowHit,
        isRightClick: Bool,
        flags: CGEventFlags
    ) -> Decision? {
        // Coarse rejection: only clicks inside the title bar band reach the
        // (comparatively expensive) AX hit test.
        guard location.y - window.bounds.minY <= InterceptorMetrics.titleBarBandHeight else {
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
            let hit = Self.trafficButton(
                at: location,
                expectedProcessIdentifier: window.processIdentifier
            )
        else {
            logger.debug("\(bundleIdentifier, privacy: .public): AX found no traffic button")
            return nil
        }

        let button = hit.button
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
        let longPressAction = variant == .left
            ? ruleEngine.action(
                forBundleIdentifier: bundleIdentifier,
                button: button,
                variant: .longPressLeft
            ) : nil

        let buttonName = String(describing: button)
        let actionName = String(describing: action)
        let summary = "\(buttonName)/\(String(describing: variant)) -> \(actionName)"
        logger.info("\(bundleIdentifier, privacy: .public): \(summary, privacy: .public)")
        if longPressAction != nil {
            // If AX cannot supply a usable tracking region, keep the native
            // click rather than swallowing a gesture that cannot be validated.
            guard let bounds = hit.bounds, bounds.width > 0, bounds.height > 0,
                  bounds.minX.isFinite, bounds.minY.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite, bounds.contains(location) else { return nil }
        }
        return Decision(action: action, buttonBounds: hit.bounds, longPressAction: longPressAction)
    }

    /// Maps a physical click to its configured variant. Modifier checks come
    /// first (⌥ then 🌐); a plain left click may become a long-press pending.
    static func clickVariant(isRightClick: Bool, flags: CGEventFlags) -> ClickVariant {
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
