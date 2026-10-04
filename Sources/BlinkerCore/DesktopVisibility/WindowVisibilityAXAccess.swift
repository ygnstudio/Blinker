import AppKit
import ApplicationServices

struct VisibleWindowSurface: Equatable, Sendable {
    let id: UInt32
    let pid: Int32
    let frame: CGRect
    let title: String?

    static func matchingIndex(frame: CGRect, title: String?, in surfaces: [Self]) -> Int? {
        let candidates = surfaces.indices.filter { index in
            let surface = surfaces[index]
            guard abs(surface.frame.minX - frame.minX) <= 1,
                  abs(surface.frame.minY - frame.minY) <= 1,
                  abs(surface.frame.width - frame.width) <= 1,
                  abs(surface.frame.height - frame.height) <= 1 else { return false }
            if let title, !title.isEmpty, let other = surface.title, !other.isEmpty {
                return title == other
            }
            return true
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

/// Every read consumes the shared scan allowance and caps the element's IPC
/// timeout. No focused-window fallback is used when a visible surface is ambiguous.
struct WindowVisibilityAXAccess {
    private var budget: WindowAXReadBudget
    let cancellation: WindowVisibilityCancellation

    init(cancellation: WindowVisibilityCancellation, deadline: TimeInterval) {
        self.cancellation = cancellation
        budget = WindowAXReadBudget(duration: min(2, max(0, deadline - ProcessInfo.processInfo.systemUptime)),
                                    requests: 1500)
    }

    var isAvailable: Bool {
        !cancellation.isCancelled && budget.isAvailable
    }

    mutating func prepare(_ element: AXUIElement) -> Bool {
        guard !cancellation.isCancelled, let timeout = budget.nextTimeout() else { return false }
        return AXUIElementSetMessagingTimeout(element, timeout) == .success
    }

    mutating func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        guard prepare(element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    mutating func bool(_ name: String, of element: AXUIElement) -> Bool? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return (value as? Bool)
    }

    mutating func string(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    mutating func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element),
              let size = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
              [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    mutating func windows(pid: Int32) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        guard prepare(app) else { return nil }
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(app, kAXWindowsAttribute as CFString, &count) == .success,
              (0 ... 100).contains(count), prepare(app) else { return nil }
        if count == 0 {
            return []
        }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(app, kAXWindowsAttribute as CFString, 0, count, &values) ==
            .success,
            let values else { return nil }
        let raw = values as [AnyObject]
        guard raw.count <= 100,
              raw.allSatisfy({ CFGetTypeID($0) == AXUIElementGetTypeID() }) else { return nil }
        return raw.map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    mutating func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        guard prepare(element) else { return false }
        var writable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &writable) == .success
            && writable.boolValue
    }

    mutating func requestMinimized(_ value: Bool, window: AXUIElement) -> Bool {
        guard AccessibilityPermission.isTrusted, prepare(window),
              !cancellation.isCancelled else { return false }
        // Cancellation/budget expiry must not lose a request already delivered.
        // cannotComplete can also mean the app accepted it but did not reply in time.
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                                  value ? kCFBooleanTrue : kCFBooleanFalse)
        return result == .success || result == .cannotComplete
    }

    static func minimizedState(of window: AXUIElement, timeout: TimeInterval) -> Bool? {
        AXUIElementSetMessagingTimeout(window, Float(timeout))
        var actual: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &actual) == .success,
              let actual, CFGetTypeID(actual) == CFBooleanGetTypeID() else { return nil }
        return actual as? Bool
    }

    mutating func raise(_ window: AXUIElement) {
        guard AccessibilityPermission.isTrusted, prepare(window), !cancellation.isCancelled else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
