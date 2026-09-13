import ApplicationServices
import CoreGraphics

/// Shared low-level AX and `CGWindowList` helpers used by the interceptor and
/// the hover overlay. All frame values are in AX (top-left origin) global
/// coordinates unless stated otherwise.
enum AXQuery {
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

        var origin = CGPoint.zero
        var size = CGSize.zero
        let originAXValue = unsafeDowncast(originValue, to: AXValue.self)
        let sizeAXValue = unsafeDowncast(sizeValue, to: AXValue.self)
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
    /// AppKit coordinates and acts as the axis pivot.
    static func setWindowFrame(_ window: AXUIElement, appKitFrame: CGRect, globalMaxY: CGFloat) {
        var position = CGPoint(x: appKitFrame.minX, y: globalMaxY - appKitFrame.maxY)
        var size = CGSize(width: appKitFrame.width, height: appKitFrame.height)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Moves and resizes a window to a frame already in AX (top-left origin)
    /// coordinates — the space `CGWindowList` reports and `elementFrame`
    /// reads, so workspace capture/restore round-trips without conversion.
    static func setWindowFrame(axFrame frame: CGRect, of window: AXUIElement) {
        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Cheaply finds the topmost standard (layer 0) on-screen window containing
    /// the point. `excludingProcessIdentifier` skips windows of a given app,
    /// e.g. Blinker's own settings window.
    static func windowUnderPoint(
        _ point: CGPoint,
        excludingProcessIdentifier excludedPID: pid_t? = nil
    ) -> WindowHit? {
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
                return nil
            }
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            return WindowHit(processIdentifier: pid, bounds: bounds, windowID: windowID)
        }
        return nil
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
