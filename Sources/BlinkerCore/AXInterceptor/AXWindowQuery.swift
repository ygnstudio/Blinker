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

    typealias WindowListProvider = (CGWindowListOption, CGWindowID) -> [[String: Any]]

    static func copyWindowList(_ options: CGWindowListOption, _ windowID: CGWindowID) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]] ?? []
    }

    /// Checks front-to-back order even on a cache hit: a cached window's
    /// exposed corner does not make it the target in an overlapping region.
    static func windowUnderPoint(
        _ point: CGPoint,
        excludingProcessIdentifier excludedPID: pid_t? = nil,
        includingTestWindow: Bool = false,
        usingCache: Bool = false,
        windowList: WindowListProvider = copyWindowList
    ) -> WindowHit? {
        var candidates: [[String: Any]]?
        if usingCache, let cached = cacheLock.withLock({ cachedWindowHit }), cached.windowID != 0 {
            let above = windowList(
                [.optionOnScreenOnly, .optionOnScreenAboveWindow, .optionIncludingWindow], cached.windowID
            )
            // If the cached window vanished or moved away, search below it too.
            if above.contains(where: { info in
                guard let hit = windowHit(from: info) else { return false }
                return hit.windowID == cached.windowID && hit.bounds.contains(point)
            }) {
                candidates = above
            }
        }
        let list = candidates ?? windowList([.optionOnScreenOnly], kCGNullWindowID)
        let hit = list.lazy.compactMap { windowHit(from: $0) }.first { $0.bounds.contains(point) }
        // An excluded foreground window blocks hits behind it.
        let result = hit.flatMap { candidate in
            let testException = includingTestWindow && HoverTestWindow.contains(candidate)
            return candidate.processIdentifier == excludedPID && !testException ? nil : candidate
        }
        cacheWindowHit(result)
        return result
    }

    /// A visible palette owns its window even where the palette extends past
    /// that window's bounds. Discard it when its owner moves, closes or minimizes.
    static func isWindowCurrent(
        _ expected: WindowHit, windowList: WindowListProvider = copyWindowList
    ) -> Bool {
        guard expected.windowID != 0 else { return false }
        return windowList([.optionOnScreenOnly, .optionIncludingWindow], expected.windowID).contains { info in
            guard let hit = windowHit(from: info) else { return false }
            return hit.windowID == expected.windowID
                && hit.processIdentifier == expected.processIdentifier
                && hit.bounds == expected.bounds
        }
    }

    private static func windowHit(from info: [String: Any]) -> WindowHit? {
        guard info[kCGWindowLayer as String] as? Int == 0,
              info[kCGWindowIsOnscreen as String] as? Bool != false,
              let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dictionary),
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let windowID = info[kCGWindowNumber as String] as? CGWindowID
        else { return nil }
        return WindowHit(processIdentifier: pid, bounds: bounds, windowID: windowID)
    }

    private static let cacheLock = NSLock()
    private static var cachedWindowHit: WindowHit?

    private static func cacheWindowHit(_ hit: WindowHit?) {
        cacheLock.withLock { cachedWindowHit = hit }
    }

    static func invalidateWindowUnderPointCache() {
        cacheWindowHit(nil)
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
