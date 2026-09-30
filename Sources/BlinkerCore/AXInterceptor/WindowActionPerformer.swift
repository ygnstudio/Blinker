import AppKit
import ApplicationServices

public protocol WindowActionPerforming: AnyObject {
    func perform(_ action: ButtonAction, window: AXUIElement, processIdentifier: pid_t)
}

/// One shared performer lets hotkeys and hover controls restore each other's
/// layout changes. AX work stays on caller worker queues, serialized by the lock.
public final class DefaultWindowActionPerformer: WindowActionPerforming {
    public static let shared = DefaultWindowActionPerformer()
    private let lock = NSLock()
    private var history = WindowLayoutHistory<WindowIdentity>()
    private let operation: ((ButtonAction, AXUIElement, pid_t) -> WindowActionResult)?

    public init() {
        operation = nil
    }

    init(operation: @escaping (ButtonAction, AXUIElement, pid_t) -> WindowActionResult) {
        self.operation = operation
    }

    public func perform(_ action: ButtonAction, window: AXUIElement, processIdentifier: pid_t) {
        if processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // The test window belongs to Blinker. A process-wide action must
            // never remove the utility or its settings during a window test.
            guard action != .quitApp, action != .hideApp else {
                ActionFeedback.report(.unsupportedWindow)
                return
            }
            // AX requests targeting our own process execute AppKit inline;
            // unlike cross-process IPC, they do not hop onto the target's main thread.
            if !Thread.isMainThread {
                DispatchQueue.main.async { [self] in
                    perform(action, window: window, processIdentifier: processIdentifier)
                }
                return
            }
        }
        let result = lock.withLock {
            operation?(action, window, processIdentifier)
                ?? execute(action, window: window, pid: processIdentifier)
        }
        ActionFeedback.report(result)
    }

    private func execute(_ action: ButtonAction, window: AXUIElement, pid: pid_t) -> WindowActionResult {
        guard AccessibilityPermission.isTrusted else { return .permissionRequired }
        AXQuery.applyMessagingTimeout(window)
        let app = NSRunningApplication(processIdentifier: pid)
        if let bundleID = app?.bundleIdentifier, SessionPause.shared.contains(bundleID) {
            return .completed
        }
        switch action {
        case .closeWindow, .minimize, .fullscreen:
            let button: TrafficButton = action == .closeWindow ? .close : action == .minimize ? .minimize :
                .zoom
            return AXQuery
                .pressButton(subrole: button.axSubrole, in: window) ? .completed : .unsupportedWindow
        case .quitApp:
            return app?.terminate() == true ? .completed : .requestRejected
        case .hideApp:
            return app?.hide() == true ? .completed : .requestRejected
        case .none, .windowManagerPanel:
            return .completed
        default:
            return performGeometry(action, window: window, pid: pid)
        }
    }

    private func performGeometry(_ action: ButtonAction, window: AXUIElement,
                                 pid: pid_t) -> WindowActionResult {
        guard let axFrame = AXQuery.elementFrame(window) else { return .unsupportedWindow }
        let current = AXQuery.appKitFrame(fromAXRect: axFrame)
        let screens = NSScreen.screens
        guard let screen = screens
            .first(where: { $0.frame.contains(CGPoint(x: current.midX, y: current.midY)) })
            ?? NSScreen.main else { return .unsupportedWindow }
        let key = WindowIdentity(pid: pid, element: window)
        let restoring = action == .restorePreviousFrame
            || history.toggleFrame(for: key, action: action, current: current) != nil
        let target: CGRect
        var destinationBounds = screen.visibleFrame
        if restoring {
            guard let previous = history.previousFrame(for: key) else { return .noPreviousLayout }
            // A disconnected monitor must not leave the restored window offscreen.
            let destination = screens.first { $0.frame.contains(CGPoint(x: previous.midX, y: previous.midY)) }
                ?? screen
            destinationBounds = destination.visibleFrame
            target = Self.fitting(previous, inside: destinationBounds)
        } else if action == .moveToNextDisplay {
            guard screens.count > 1,
                  let index = screens.firstIndex(of: screen) else { return .noOtherDisplay }
            let destination = screens[(index + 1) % screens.count].visibleFrame
            destinationBounds = destination
            target = WindowGeometry.transferredFrame(current, from: screen.visibleFrame, to: destination)
        } else {
            guard let placement = WindowPlacement(action: action) else { return .unsupportedWindow }
            target = WindowGeometry.targetFrame(
                for: placement,
                originalFrame: current,
                in: screen.visibleFrame
            )
        }
        guard AXQuery.setWindowFrame(window, appKitFrame: target, globalMaxY: AXQuery.coordinatePivotY),
              let actualAX = AXQuery.elementFrame(window) else { return .unsupportedWindow }
        var actual = AXQuery.appKitFrame(fromAXRect: actualAX)
        guard Self.accepted(actual: actual, current: current, target: target) else { return .requestRejected }
        let constrained = Self.isConstrained(actual, target: target)
        if constrained {
            actual = keepVisible(actual, window: window, inside: destinationBounds)
        }
        recordLayout(key: key, action: action, before: current, after: actual, restoring: restoring)
        return constrained ? .sizeConstrained : .completed
    }

    private func recordLayout(key: WindowIdentity, action: ButtonAction,
                              before: CGRect, after: CGRect, restoring: Bool) {
        if restoring {
            history.didRestore(key)
        } else {
            history.record(key: key, action: action, before: before, after: after)
        }
    }

    private static func isConstrained(_ actual: CGRect, target: CGRect) -> Bool {
        actual.width > target.width + 3 || actual.height > target.height + 3
    }

    private static func accepted(actual: CGRect, current: CGRect, target: CGRect) -> Bool {
        !WindowLayoutHistory<WindowIdentity>.matches(actual, current)
            || WindowLayoutHistory<WindowIdentity>.matches(actual, target)
    }

    private func keepVisible(_ actual: CGRect, window: AXUIElement, inside bounds: CGRect) -> CGRect {
        let corrected = CGRect(
            x: max(bounds.minX, min(actual.minX, bounds.maxX - actual.width)),
            y: max(bounds.minY, min(actual.minY, bounds.maxY - actual.height)),
            width: actual.width, height: actual.height
        )
        AXQuery.setWindowFrame(window, appKitFrame: corrected, globalMaxY: AXQuery.coordinatePivotY)
        return AXQuery.elementFrame(window).map(AXQuery.appKitFrame) ?? actual
    }

    private static func fitting(_ frame: CGRect, inside visible: CGRect) -> CGRect {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                      y: min(max(frame.minY, visible.minY), visible.maxY - height), width: width,
                      height: height)
    }
}

private struct WindowIdentity: Hashable {
    let pid: pid_t
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(CFHash(element))
    }
}
