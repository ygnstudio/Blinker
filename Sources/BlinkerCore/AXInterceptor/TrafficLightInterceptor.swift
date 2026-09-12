import AppKit
import ApplicationServices
import CoreGraphics

/// Intercepts mouse clicks on traffic light buttons of other applications and
/// remaps them according to the active rules.
///
/// Pipeline for every left mouse down:
/// 1. Locate the on-screen window under the cursor (cheap `CGWindowList` probe)
///    and discard the click early when its title bar region is not involved.
/// 2. Hit-test the exact AX element under the cursor and read its subrole to
///    identify close / minimize / zoom buttons.
/// 3. Ask the `RuleEngine` what to do; `nil` means pass the event through.
/// 4. Otherwise swallow the event and perform the remapped action instead.
public final class TrafficLightInterceptor {
    private let ruleEngine: RuleEngine
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let workQueue = DispatchQueue(label: "com.ygnstudio.blinker.interceptor")

    public init(ruleEngine: RuleEngine) {
        self.ruleEngine = ruleEngine
    }

    public var isRunning: Bool { eventTap != nil }

    /// Installs the event tap. Returns `false` when the Accessibility
    /// permission is missing or the system refuses the tap.
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AccessibilityPermission.isTrusted else { return false }

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
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
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
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard eventType == .leftMouseDown else { return Unmanaged.passUnretained(event) }

        let location = event.location
        guard let window = Self.windowUnderPoint(location) else { return Unmanaged.passUnretained(event) }

        // Coarse rejection: only clicks inside the title bar band reach the
        // (comparatively expensive) AX hit test.
        let titleBarBandHeight: CGFloat = 32
        guard location.y - window.bounds.minY <= titleBarBandHeight else {
            return Unmanaged.passUnretained(event)
        }

        guard
            let app = NSRunningApplication(processIdentifier: window.processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else { return Unmanaged.passUnretained(event) }

        // Cheap second rejection: no rule for this app at all.
        guard ruleEngine.hasRule(forBundleIdentifier: bundleIdentifier) else {
            return Unmanaged.passUnretained(event)
        }

        guard
            let button = Self.trafficButton(
                at: location,
                expectedProcessIdentifier: window.processIdentifier
            ),
            let action = ruleEngine.action(forBundleIdentifier: bundleIdentifier, button: button)
        else { return Unmanaged.passUnretained(event) }

        guard action.isImplemented else { return Unmanaged.passUnretained(event) }

        // Swallow the original click and perform the remapped action.
        workQueue.async { [weak self] in
            self?.perform(action, button: button, processIdentifier: window.processIdentifier)
        }
        return nil
    }

    // MARK: - Action execution

    private func perform(_ action: ButtonAction, button: TrafficButton, processIdentifier: pid_t) {
        let runningApp = NSRunningApplication(processIdentifier: processIdentifier)

        switch (button, action) {
        case (.close, .closeWindow), (.minimize, .minimize), (.zoom, .fullscreen):
            // The remapped action equals a native press of the clicked button.
            Self.pressElement(subrole: button.axSubrole, processIdentifier: processIdentifier)
        case (_, .quitApp):
            runningApp?.terminate()
        case (_, .hideApp):
            runningApp?.hide()
        case (_, .maximize):
            Self.zoomWindowWithoutFullscreen(processIdentifier: processIdentifier)
        case (_, .closeWindow), (_, .minimize), (_, .fullscreen), (_, .none):
            break
        case (_, .tileLeft), (_, .tileRight):
            break // Planned for a follow-up release; treated as pass-through.
        }
    }

    // MARK: - AX helpers

    /// Identifies the traffic button under the cursor via an AX hit test.
    private static func trafficButton(
        at point: CGPoint,
        expectedProcessIdentifier processIdentifier: pid_t
    ) -> TrafficButton? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == processIdentifier else { return nil }

        guard let subrole = stringAttribute(element, kAXSubroleAttribute) else { return nil }
        return TrafficButton(axSubrole: subrole)
    }

    /// Finds a button by subrole inside the focused window of an app and presses it.
    private static func pressElement(subrole: String, processIdentifier: pid_t) {
        guard let window = focusedWindowElement(processIdentifier: processIdentifier) else { return }
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
            let children = childrenRef as? [AXUIElement]
        else { return }

        for child in children {
            guard stringAttribute(child, kAXSubroleAttribute) == subrole else { continue }
            AXUIElementPerformAction(child, kAXPressAction as CFString)
            return
        }
    }

    /// Zooms the focused window to fill the screen without entering fullscreen.
    private static func zoomWindowWithoutFullscreen(processIdentifier: pid_t) {
        guard let window = focusedWindowElement(processIdentifier: processIdentifier) else { return }
        let zoomAttribute = "AXZoomWindow" as CFString
        AXUIElementSetAttributeValue(window, zoomAttribute, kCFBooleanTrue)
    }

    private static func focusedWindowElement(processIdentifier: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowRef: CFTypeRef?
        let focusedWindow = kAXFocusedWindowAttribute as CFString
        let result = AXUIElementCopyAttributeValue(appElement, focusedWindow, &windowRef)
        guard result == .success, let window = windowRef else { return nil }
        return unsafeDowncast(window, to: AXUIElement.self)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    // MARK: - Window lookup

    private struct WindowHit {
        let processIdentifier: pid_t
        let bounds: CGRect
    }

    /// Cheaply finds the topmost standard on-screen window containing the point.
    private static func windowUnderPoint(_ point: CGPoint) -> WindowHit? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in windowList {
            guard info[kCGWindowLayer as String] as? Int == 0 else { continue }
            guard
                let boundsDictionary = info[kCGWindowBounds as String],
                // CGWindowList values are toll-free-bridged CF objects.
                // swiftlint:disable:next force_cast
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary),
                bounds.contains(point)
            else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return WindowHit(processIdentifier: pid, bounds: bounds)
        }
        return nil
    }
}

// MARK: - Subrole mapping

private extension TrafficButton {
    /// The AX subrole that identifies this button inside another app's window.
    var axSubrole: String {
        switch self {
        case .close: return "AXCloseButton"
        case .minimize: return "AXMinimizeButton"
        case .zoom: return "AXFullScreenButton"
        }
    }

    init?(axSubrole: String) {
        switch axSubrole {
        case "AXCloseButton": self = .close
        case "AXMinimizeButton": self = .minimize
        case "AXZoomButton", "AXFullScreenButton": self = .zoom
        default: return nil
        }
    }
}

private extension ButtonAction {
    /// Actions with a v1 implementation; everything else passes through.
    var isImplemented: Bool {
        switch self {
        case .closeWindow, .quitApp, .minimize, .hideApp, .maximize, .fullscreen, .none:
            return true
        case .tileLeft, .tileRight:
            return false
        }
    }
}
