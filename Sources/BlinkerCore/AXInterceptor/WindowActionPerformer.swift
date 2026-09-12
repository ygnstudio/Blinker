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
    /// `button` is the traffic button the action was triggered from; remaps
    /// that equal the native behavior press the original button via AX.
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
        button: TrafficButton,
        window: AXUIElement,
        processIdentifier: pid_t
    ) {
        let runningApp = NSRunningApplication(processIdentifier: processIdentifier)
        switch (button, action) {
        case (.close, .closeWindow), (.minimize, .minimize), (.zoom, .fullscreen):
            // The remapped action equals a native press of the clicked button.
            AXQuery.pressButton(subrole: button.axSubrole, in: window)
        case (_, .quitApp):
            logger.info("terminating pid \(processIdentifier)")
            runningApp?.terminate()
        case (_, .hideApp):
            logger.info("hiding pid \(processIdentifier)")
            runningApp?.hide()
        case (_, .maximize):
            logger.info("zooming pid \(processIdentifier) window")
            maximize(window)
        case (_, .tileLeft):
            logger.info("tiling pid \(processIdentifier) window left")
            tile(window, side: .left)
        case (_, .tileRight):
            logger.info("tiling pid \(processIdentifier) window right")
            tile(window, side: .right)
        case (_, .closeWindow), (_, .minimize), (_, .fullscreen), (_, .none):
            break
        }
    }

    // MARK: - Geometry actions

    private enum TileSide {
        case left
        case right
    }

    /// Zooms the window to fill the visible frame of the screen it is mostly
    /// on, without entering fullscreen.
    ///
    /// The `AXZoomWindow` attribute is read-only in practice, so the zoom is
    /// performed by setting the window position and size directly — the same
    /// approach Rectangle and Magnet use.
    private func maximize(_ window: AXUIElement) {
        guard let appKitFrame = Self.appKitFrame(of: window) else { return }
        guard let visibleFrame = Self.screen(containing: appKitFrame)?.visibleFrame else { return }
        AXQuery.setWindowFrame(window, appKitFrame: visibleFrame, globalMaxY: Self.globalMaxY)
    }

    /// Tiles the window to the left or right half of its screen's visible
    /// frame; the screen is chosen by the window center.
    private func tile(_ window: AXUIElement, side: TileSide) {
        guard let appKitFrame = Self.appKitFrame(of: window) else { return }
        guard let visibleFrame = Self.screen(containing: appKitFrame)?.visibleFrame else { return }
        let halfWidth = visibleFrame.width / 2
        let x = side == .left ? visibleFrame.minX : visibleFrame.midX
        let frame = CGRect(x: x, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        AXQuery.setWindowFrame(window, appKitFrame: frame, globalMaxY: Self.globalMaxY)
    }

    /// The primary screen's top edge in AppKit coordinates; the pivot for
    /// converting between AppKit and AX (top-left origin) frames.
    private static var globalMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
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
