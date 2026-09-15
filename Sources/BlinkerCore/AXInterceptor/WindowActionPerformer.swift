import AppKit
import ApplicationServices
import os

/// Executes window-management actions on a specific AX window.
///
/// Implementations receive the already-resolved target window and its process
/// identifier; resolving *which* window was clicked stays the caller's job
/// (frame matching in the interceptor, AX lookup in the hover overlay).
public protocol WindowActionPerforming: AnyObject {
    /// Performs `action` on `window` (owned by `processIdentifier`).
    ///
    /// `button` is the traffic button the action was triggered from —
    /// informational only. Remaps that equal a native behavior press the
    /// *action's* native button (e.g. red → minimize presses the yellow
    /// button), so implementations must not assume it equals `button`.
    func perform(
        _ action: ButtonAction,
        button: TrafficButton,
        window: AXUIElement,
        processIdentifier: pid_t
    )
}

/// The production implementation, driven by AX APIs and `NSRunningApplication`.
public final class DefaultWindowActionPerformer: WindowActionPerforming {
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "action-performer")

    public init() {}

    public func perform(
        _ action: ButtonAction,
        button _: TrafficButton,
        window: AXUIElement,
        processIdentifier: pid_t
    ) {
        let runningApp = NSRunningApplication(processIdentifier: processIdentifier)
        switch action {
        case .closeWindow, .minimize, .fullscreen:
            // The remap equals a native press — possibly of a *different*
            // button than the one clicked (e.g. red → minimize), so the
            // press targets the action's native button, not the clicked one.
            AXQuery.pressButton(subrole: Self.nativeSubrole(for: action), in: window)
        case .quitApp:
            logger.info("terminating pid \(processIdentifier)")
            runningApp?.terminate()
        case .hideApp:
            logger.info("hiding pid \(processIdentifier)")
            runningApp?.hide()
        case .none, .windowManagerPanel:
            // `.windowManagerPanel` is overlay-only and never routed here.
            break
        default:
            performGeometry(action, window: window, processIdentifier: processIdentifier)
        }
    }

    /// Handles the frame-manipulation actions; the screen is chosen by the
    /// window center and the target frame math lives in `WindowGeometry`.
    private func performGeometry(
        _ action: ButtonAction,
        window: AXUIElement,
        processIdentifier: pid_t
    ) {
        if action == .moveToNextDisplay {
            logger.info("moving pid \(processIdentifier) window to next display")
            moveToNextDisplay(window)
            return
        }
        guard let placement = WindowPlacement(action: action) else { return }
        logger.info("placing pid \(processIdentifier) window: \(String(describing: placement))")
        place(window, placement: placement)
    }

    /// The AX subrole of the button whose native behavior matches `action`.
    private static func nativeSubrole(for action: ButtonAction) -> String {
        switch action {
        case .closeWindow: TrafficButton.close.axSubrole
        case .minimize: TrafficButton.minimize.axSubrole
        case .fullscreen: TrafficButton.zoom.axSubrole
        default: TrafficButton.close.axSubrole
        }
    }

    // MARK: - Geometry actions

    /// Zooms the window to fill the visible frame of the screen it is mostly
    /// on, without entering fullscreen.
    ///
    /// The `AXZoomWindow` attribute is read-only in practice, so the zoom is
    /// performed by setting the window position and size directly — the same
    /// approach Rectangle and Magnet use.
    private func place(_ window: AXUIElement, placement: WindowPlacement) {
        guard let appKitFrame = Self.appKitFrame(of: window) else { return }
        guard let visibleFrame = Self.screen(containing: appKitFrame)?.visibleFrame else { return }
        let target = WindowGeometry.targetFrame(
            for: placement,
            originalFrame: appKitFrame,
            in: visibleFrame
        )
        AXQuery.setWindowFrame(window, appKitFrame: target, globalMaxY: Self.globalMaxY)
    }

    /// Moves the window to the next display (wrapping around), keeping its
    /// size and centering it in the target screen's visible frame.
    private func moveToNextDisplay(_ window: AXUIElement) {
        guard NSScreen.screens.count > 1,
              let appKitFrame = Self.appKitFrame(of: window),
              let current = Self.screen(containing: appKitFrame),
              let index = NSScreen.screens.firstIndex(of: current)
        else { return }
        let target = NSScreen.screens[(index + 1) % NSScreen.screens.count]
        let visible = target.visibleFrame
        var frame = appKitFrame
        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        frame.origin = CGPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        AXQuery.setWindowFrame(window, appKitFrame: frame, globalMaxY: Self.globalMaxY)
    }

    /// The primary screen's top edge in AppKit coordinates; the pivot for
    /// converting between AppKit and AX (top-left origin) frames.
    private static var globalMaxY: CGFloat {
        AXQuery.coordinatePivotY
    }

    /// Reads the window frame and converts it from AX to AppKit coordinates.
    private static func appKitFrame(of window: AXUIElement) -> CGRect? {
        guard let axFrame = AXQuery.elementFrame(window) else { return nil }
        let maxY = globalMaxY
        return CGRect(
            x: axFrame.minX,
            y: maxY - axFrame.maxY,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    /// Finds the screen containing the frame's center, falling back to the
    /// main screen.
    private static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        } ?? NSScreen.main
    }
}
