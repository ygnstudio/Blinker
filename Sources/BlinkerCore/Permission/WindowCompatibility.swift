import AppKit
import ApplicationServices

public struct WindowCompatibilityReport: Sendable {
    public let permissionGranted: Bool
    public let windowFound: Bool
    public let buttons: [TrafficButton]
    public let canMove: Bool
    public let canResize: Bool
}

/// Read-only inspection; does not click controls or move the inspected window.
public enum WindowCompatibility {
    public static func inspect(bundleID: String, completion: @escaping (WindowCompatibilityReport) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let report = inspect(bundleID: bundleID)
            DispatchQueue.main.async { completion(report) }
        }
    }

    private static func inspect(bundleID: String) -> WindowCompatibilityReport {
        let trusted = AccessibilityPermission.isTrusted
        guard trusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let window = AXQuery.focusedWindowElement(processIdentifier: app.processIdentifier)
        else {
            return WindowCompatibilityReport(permissionGranted: trusted, windowFound: false,
                                             buttons: [], canMove: false, canResize: false)
        }
        AXQuery.applyMessagingTimeout(window)
        let buttons = availableButtons { attribute in
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success &&
                value !=
                nil
        }
        return WindowCompatibilityReport(permissionGranted: true, windowFound: true, buttons: buttons,
                                         canMove: isSettable(kAXPositionAttribute, window: window),
                                         canResize: isSettable(kAXSizeAttribute, window: window))
    }

    static func availableButtons(attributeExists: (String) -> Bool) -> [TrafficButton] {
        TrafficButton.allCases.filter { button in
            let attributes: [String] = switch button {
            case .close: [kAXCloseButtonAttribute]
            case .minimize: [kAXMinimizeButtonAttribute]
            case .zoom: [kAXFullScreenButtonAttribute, kAXZoomButtonAttribute]
            }
            return attributes.contains(where: attributeExists)
        }
    }

    private static func isSettable(_ attribute: String, window: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success
            && settable.boolValue
    }
}

/// Explicit exception for the one native test window. Settings and all other
/// Blinker windows remain excluded from hover detection.
public enum HoverTestWindow {
    private static let lock = NSLock()
    private static var windowID: CGWindowID?

    public static func register(windowID: CGWindowID?) {
        lock.withLock { self.windowID = windowID }
    }

    static func contains(_ hit: AXQuery.WindowHit) -> Bool {
        lock.withLock { hit.processIdentifier == ProcessInfo.processInfo.processIdentifier
            && hit.windowID == windowID
        }
    }
}
