import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Intercepts mouse clicks on traffic light buttons of other applications and
/// remaps them according to the active rules.
///
/// Pipeline for every left mouse down:
/// 1. Locate the on-screen window under the cursor (cheap `CGWindowList` probe)
///    and discard the click early when its title bar region is not involved.
/// 2. Hit-test the exact AX element under the cursor and read its subrole to
///    identify close / minimize / zoom buttons.
/// 3. Ask the `RuleEngine` what to do; `nil` means pass the event through.
/// 4. Otherwise swallow the event, resolve the clicked AX window and delegate
///    the action to the `WindowActionPerformer`.
public final class TrafficLightInterceptor {
    private let ruleEngine: RuleEngine
    private let actionPerformer: WindowActionPerforming
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.interceptor")
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "interceptor")

    private static let titleBarBandHeight: CGFloat = 32

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

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(
                    1 << CGEventType.leftMouseDown.rawValue
                ),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            logger.error("CGEvent.tapCreate returned nil (hidTap, headInsert, defaultTap)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        logger.info("event tap installed and enabled")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
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
        guard eventType == .leftMouseDown else { return Unmanaged.passUnretained(event) }

        // A click just consumed by a hover overlay panel must not be
        // re-interpreted here (the tap fires before window routing).
        guard !OverlayClickGate.isSuppressed else {
            logger.debug("click suppressed (consumed by overlay panel); pass-through")
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        guard let window = AXQuery.windowUnderPoint(location) else { return Unmanaged.passUnretained(event) }
        guard let decision = resolveDecision(location: location, window: window) else {
            return Unmanaged.passUnretained(event)
        }

        // Swallow the original click and perform the remapped action.
        workQueue.async { [weak self] in
            self?.perform(
                decision.action,
                button: decision.button,
                window: window
            )
        }
        return nil
    }

    /// Resolves whether the click should be intercepted and with which action.
    /// Logs every rejection reason; returns `nil` for pass-through.
    private func resolveDecision(
        location: CGPoint,
        window: AXQuery.WindowHit
    ) -> (button: TrafficButton, action: ButtonAction)? {
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

        guard let action = ruleEngine.action(forBundleIdentifier: bundleIdentifier, button: button) else {
            logger
                .debug(
                    "\(bundleIdentifier, privacy: .public): \(button.axSubrole, privacy: .public) maps to nil"
                )
            return nil
        }

        let buttonName = String(describing: button)
        let actionName = String(describing: action)
        let summary = "\(buttonName) -> \(actionName)"
        logger.info("\(bundleIdentifier, privacy: .public): \(summary, privacy: .public)")
        return (button, action)
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
