import AppKit
import ApplicationServices
import CoreGraphics

/// Shared low-level AX and `CGWindowList` helpers used by the interceptor and
/// the hover overlay. All frame values are in AX (top-left origin) global
/// coordinates unless stated otherwise.
enum AXQuery {
    /// The y-axis pivot between AppKit (bottom-left origin) and AX/CG
    /// (top-left origin) global coordinates: the primary screen's top edge in
    /// AppKit space. `NSScreen.screens` always reports the primary screen at
    /// index 0 with origin (0, 0), so this equals the primary screen's
    /// height. Never use `max()` across all screens here — a secondary
    /// display arranged above the primary would shift every converted frame.
    static var coordinatePivotY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// Converts a rect from AX (top-left origin) global coordinates into
    /// AppKit (bottom-left origin) global coordinates, flipping around the
    /// primary screen's top edge. Shared by every overlay panel so the
    /// conversion cannot drift between them.
    static func appKitFrame(fromAXRect axFrame: CGRect) -> CGRect {
        let globalMaxY = coordinatePivotY
        return CGRect(
            x: axFrame.minX,
            y: globalMaxY - axFrame.maxY,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    /// The on-screen window a cursor point belongs to, as seen by `CGWindowList`.
    struct WindowHit {
        let processIdentifier: pid_t
        let bounds: CGRect
        /// The CG window number, used for screen-capture sampling.
        var windowID: CGWindowID = 0
    }

    /// Bounds within this distance (in points) count as the same window when
    /// matching a `CGWindowList` hit against an AX window frame.
    static let frameMatchTolerance: CGFloat = 1

    /// AX calls are synchronous IPC into the target app; a hung app would
    /// otherwise block the caller for seconds. Cap every element at 250 ms.
    static let messagingTimeout: Float = 0.25

    /// Applies the capped messaging timeout to an element.
    static func applyMessagingTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    /// Reads a string-valued AX attribute.
    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// Reads an element's frame in AX (top-left origin) coordinates.
    static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var originRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &originRef) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let originValue = originRef, let sizeValue = sizeRef
        else { return nil }

        // Validate the CF types before unwrapping: a misbehaving app can
        // return something other than an AXValue, which would trap inside
        // AXValueGetValue. Swift forbids `as?` on CF types (it claims the
        // downcast always succeeds), so validate via type IDs instead.
        guard
            CFGetTypeID(originValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        let originAXValue = unsafeDowncast(originValue, to: AXValue.self)
        let sizeAXValue = unsafeDowncast(sizeValue, to: AXValue.self)

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(originAXValue, .cgPoint, &origin),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Resolves the AX window matching a `CGWindowList` hit by frame, falling
    /// back to the app's focused window when no frame matches closely.
    static func resolveWindow(processIdentifier: pid_t, bounds hitBounds: CGRect) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        applyMessagingTimeout(appElement)

        var windowsRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) ==
            .success,
            let windows = windowsRef as? [AXUIElement]
        else {
            return focusedWindowElement(processIdentifier: processIdentifier)
        }

        let matched = windows.first { window in
            guard let frame = elementFrame(window) else { return false }
            return abs(frame.minX - hitBounds.minX) <= frameMatchTolerance
                && abs(frame.minY - hitBounds.minY) <= frameMatchTolerance
                && abs(frame.width - hitBounds.width) <= frameMatchTolerance
                && abs(frame.height - hitBounds.height) <= frameMatchTolerance
        }
        return matched ?? focusedWindowElement(processIdentifier: processIdentifier)
    }

    static func focusedWindowElement(processIdentifier: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        applyMessagingTimeout(appElement)
        var windowRef: CFTypeRef?
        let focusedWindow = kAXFocusedWindowAttribute as CFString
        let result = AXUIElementCopyAttributeValue(appElement, focusedWindow, &windowRef)
        guard result == .success, let window = windowRef else { return nil }
        // Type-check the CF value before downcasting (see elementFrame).
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(window, to: AXUIElement.self)
    }

    /// Finds a button by subrole among the window's direct children and
    /// performs `AXPress` on it. Returns `false` when the button could not be
    /// found or the press failed, so callers can surface (or log) the miss —
    /// the click that triggered it has already been swallowed.
    @discardableResult
    static func pressButton(subrole: String, in window: AXUIElement) -> Bool {
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
            let children = childrenRef as? [AXUIElement]
        else { return false }

        for child in children {
            guard stringAttribute(child, kAXSubroleAttribute) == subrole else { continue }
            return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
        }
        return false
    }

    /// Moves and resizes a window to a frame given in AppKit (bottom-left
    /// origin) coordinates; `globalMaxY` is the primary screen's top edge in
    /// AppKit coordinates and acts as the axis pivot. Size is applied before
    /// position: apps that clamp to min/max sizes resize around the window's
    /// center, which would undo a position set first. Returns whether the
    /// position write was accepted.
    @discardableResult
    static func setWindowFrame(_ window: AXUIElement, appKitFrame: CGRect, globalMaxY: CGFloat) -> Bool {
        var size = CGSize(width: appKitFrame.width, height: appKitFrame.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        var position = CGPoint(x: appKitFrame.minX, y: globalMaxY - appKitFrame.maxY)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, positionValue
        ) == .success
    }

    /// Moves and resizes a window to a frame already in AX (top-left origin)
    /// coordinates — the space `CGWindowList` reports and `elementFrame`
    /// reads, so workspace capture/restore round-trips without conversion.
    /// Size first, then position (see the AppKit variant above). Returns
    /// whether the position write was accepted — the honest signal that the
    /// window actually moved (some apps reject size writes on fixed-size
    /// windows while still accepting the move).
    @discardableResult
    static func setWindowFrame(axFrame frame: CGRect, of window: AXUIElement) -> Bool {
        var size = CGSize(width: frame.width, height: frame.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        var position = CGPoint(x: frame.minX, y: frame.minY)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, positionValue
        ) == .success
    }

    /// Cheaply finds the topmost standard (layer 0) on-screen window containing
    /// the point. `excludingProcessIdentifier` skips windows of a given app,
    /// e.g. Blinker's own settings window.
    ///
    /// `usingCache` serves a validated cached hit instead of walking the
    /// whole `CGWindowList` — intended for hot paths (per-mouse-move hover
    /// detection), not for click decisions. The cached hit is re-validated
    /// with a single-window query (still on screen, layer 0, current bounds
    /// containing the point); residual staleness is limited to z-order
    /// changes directly under a stationary cursor, and the cache is
    /// invalidated on drags and app activations by the hover controller.
    static func windowUnderPoint(
        _ point: CGPoint,
        excludingProcessIdentifier excludedPID: pid_t? = nil,
        usingCache: Bool = false
    ) -> WindowHit? {
        if usingCache, let cached = cachedWindowHit {
            if cached.processIdentifier != excludedPID,
               let validated = validatedCachedHit(cached, at: point) {
                return validated
            }
        }

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
            if let excludedPID, pid == excludedPID {
                // The topmost window at this point belongs to us (settings
                // window, overlay host); never fall through to windows hidden
                // behind it.
                cacheWindowHit(nil)
                return nil
            }
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let hit = WindowHit(processIdentifier: pid, bounds: bounds, windowID: windowID)
            cacheWindowHit(hit)
            return hit
        }
        cacheWindowHit(nil)
        return nil
    }

    // MARK: - Hot-path hit cache

    private static let cacheLock = NSLock()
    private static var cachedWindowHit: WindowHit?

    private static func cacheWindowHit(_ hit: WindowHit?) {
        cacheLock.withLock { cachedWindowHit = hit }
    }

    /// Drops the hot-path cache; called when the window order may have
    /// changed without the cursor moving (drag stand-down, app activation).
    static func invalidateWindowUnderPointCache() {
        cacheWindowHit(nil)
    }

    /// Re-validates a cached hit with a single-window `CGWindowList` query —
    /// far cheaper than the full copy — returning the hit with its *current*
    /// bounds, or `nil` when the window disappeared, left the screen or no
    /// longer contains the point.
    private static func validatedCachedHit(_ cached: WindowHit, at point: CGPoint) -> WindowHit? {
        guard cached.windowID != 0 else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], cached.windowID)
            as? [[String: Any]] ?? []
        guard let info = list.first else { return nil }
        guard
            info[kCGWindowLayer as String] as? Int == 0,
            let pid = info[kCGWindowOwnerPID as String] as? pid_t,
            pid == cached.processIdentifier,
            let boundsDictionary = info[kCGWindowBounds as String],
            // swiftlint:disable:next force_cast
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary),
            bounds.contains(point)
        else { return nil }
        return WindowHit(processIdentifier: pid, bounds: bounds, windowID: cached.windowID)
    }
}

extension TrafficButton {
    /// The AX subrole that identifies this button inside another app's window.
    var axSubrole: String {
        switch self {
        case .close: "AXCloseButton"
        case .minimize: "AXMinimizeButton"
        case .zoom: "AXFullScreenButton"
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
