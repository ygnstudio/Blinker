import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Drag-to-snap: while the user drags a window by its title bar toward a
/// screen edge or corner, a translucent preview of the target frame appears;
/// releasing the mouse snaps the window into place (Rectangle-style).
///
/// The event tap is observe-only (`listenOnly`) — dragging must never be
/// swallowed, only watched. A drag counts as a window drag when the mouse
/// down landed inside the title-bar band of a standard on-screen window that
/// is not Blinker's own.
public final class WindowSnapper {
    private let actionPerformer: WindowActionPerforming
    /// Hosts the observe-only tap on a dedicated thread (never the main run
    /// loop, so drag callbacks cannot stall UI work) with the shared,
    /// ordered teardown.
    private let tapHost = EventTapThreadHost(threadName: "snapper-tap")
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "snapper")

    private static let titleBarBandHeight: CGFloat = 32
    /// Guards the mutable drag state below (tap callback runs on the tap
    /// thread; `isEnabled` is toggled from the settings UI).
    private let stateLock = NSLock()
    private var isEnabled = true
    private var drag: DragContext?

    /// One screen's placement geometry, snapshotted at drag start.
    struct ScreenGeometry {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// Bookkeeping for one window drag, from mouse down to mouse up.
    private struct DragContext {
        let processIdentifier: pid_t
        /// The window's `CGWindowList` bounds at drag start (used to resolve
        /// the AX window; resolution falls back to the app's focused window,
        /// which is correct mid-drag).
        let initialBounds: CGRect
        /// Screens snapshot taken at drag start: the per-move-event zone
        /// math must not re-read `NSScreen.screens` (an AppKit global walk)
        /// on every drag event, and not from the tap thread.
        let screens: [ScreenGeometry]
        /// The placement currently previewed, if any.
        var previewedPlacement: WindowPlacement?
    }

    private var previewPanel: SnapPreviewPanel?

    public init(actionPerformer: WindowActionPerforming) {
        self.actionPerformer = actionPerformer
    }

    public var isRunning: Bool {
        tapHost.isRunning
    }

    /// Enables or disables zone detection live; the tap keeps running so the
    /// settings toggle takes effect without restarting anything.
    public func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        isEnabled = enabled
        stateLock.unlock()
        if !enabled {
            hidePreview()
        }
    }

    /// Installs the observe-only tap. Returns `false` when the Accessibility
    /// permission is missing or the system refuses the tap.
    @discardableResult
    public func start() -> Bool {
        guard !tapHost.isRunning else { return true }
        guard AccessibilityPermission.isTrusted else {
            logger.error("start aborted: accessibility permission missing")
            return false
        }

        let callback: CGEventTapCallBack = { _, eventType, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            let snapper = Unmanaged<WindowSnapper>.fromOpaque(userData).takeUnretainedValue()
            snapper.handle(event: event, eventType: eventType)
            return Unmanaged.passUnretained(event)
        }

        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
        )

        guard
            tapHost.start(
                mask: mask,
                options: .listenOnly,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            logger.error("CGEvent.tapCreate returned nil (snapper, listenOnly)")
            return false
        }
        logger.info("snapper tap installed (observe-only)")
        return true
    }

    public func stop() {
        tapHost.stop()
        hidePreview()
    }

    deinit {
        stop()
    }

    // MARK: - Event handling

    private func handle(event: CGEvent, eventType: CGEventType) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            tapHost.enableTap()
            return
        }

        switch eventType {
        case .leftMouseDown:
            // CG (top-left origin) space — matches CGWindowList bounds.
            handleDragStart(at: event.location)
        case .leftMouseDragged:
            // AppKit (bottom-left origin) space — matches the snapshotted
            // screen frames and SnapZones fixtures.
            handleDragMove(to: Self.appKitPoint(from: event.location))
        case .leftMouseUp:
            handleDragEnd(to: Self.appKitPoint(from: event.location))
        default:
            break
        }
    }

    /// Converts a CG (top-left origin) tap point into AppKit global
    /// (bottom-left origin) coordinates — the space `NSScreen` frames and
    /// `SnapZones` live in. Without this flip every snap zone is mirrored
    /// vertically (drag-to-top resolved to a bottom tile).
    static func appKitPoint(from cgPoint: CGPoint, pivotY: CGFloat) -> CGPoint {
        CGPoint(x: cgPoint.x, y: pivotY - cgPoint.y)
    }

    /// Instance convenience using the primary screen's top edge as the pivot.
    static func appKitPoint(from cgPoint: CGPoint) -> CGPoint {
        appKitPoint(from: cgPoint, pivotY: AXQuery.coordinatePivotY)
    }

    /// Arms the drag context when a mouse down could start a window drag.
    /// Runs once per drag, so this is the only place that walks the window
    /// list and reads `NSScreen.screens` — the per-move hot path uses the
    /// snapshot captured here.
    private func handleDragStart(at location: CGPoint) {
        stateLock.lock()
        let enabled = isEnabled
        stateLock.unlock()
        guard enabled else { return }

        guard
            let hit = AXQuery.windowUnderPoint(
                location,
                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            // Only title-bar drags count, so in-app dragging (text selection,
            // file drags) never triggers a snap.
            location.y - hit.bounds.minY <= Self.titleBarBandHeight
        else { return }

        let screens = NSScreen.screens.map { screen in
            ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        stateLock.lock()
        drag = DragContext(
            processIdentifier: hit.processIdentifier,
            initialBounds: hit.bounds,
            screens: screens,
            previewedPlacement: nil
        )
        stateLock.unlock()
    }

    /// - Parameter appKitLocation: Cursor in AppKit global coordinates.
    private func handleDragMove(to appKitLocation: CGPoint) {
        stateLock.lock()
        guard let context = drag, isEnabled else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let screen = Self.screen(containing: appKitLocation, in: context.screens) else { return }
        let visibleFrame = screen.visibleFrame
        guard let placement = SnapZones.placement(at: appKitLocation, in: visibleFrame) else {
            hidePreview()
            return
        }

        let target = WindowGeometry.targetFrame(
            for: placement,
            originalFrame: .zero,
            in: visibleFrame
        )
        showPreview(target)
        stateLock.lock()
        drag?.previewedPlacement = placement
        stateLock.unlock()
    }

    /// - Parameter appKitLocation: Cursor in AppKit global coordinates.
    private func handleDragEnd(to appKitLocation: CGPoint) {
        stateLock.lock()
        let context = drag
        drag = nil
        stateLock.unlock()
        hidePreview()

        guard let context, let placement = context.previewedPlacement else { return }
        guard
            let screen = Self.screen(containing: appKitLocation, in: context.screens)
        else { return }
        let target = WindowGeometry.targetFrame(
            for: placement,
            originalFrame: .zero,
            in: screen.visibleFrame
        )

        // Mid-drag the dragged window is the app's focused window; frame
        // matching against the stale initial bounds fails, which the
        // fallback handles.
        guard
            let window = AXQuery.resolveWindow(
                processIdentifier: context.processIdentifier,
                bounds: context.initialBounds
            )
        else { return }

        logger.info("snapping pid \(context.processIdentifier) to \(String(describing: placement))")
        AXQuery.setWindowFrame(
            window,
            appKitFrame: target,
            globalMaxY: AXQuery.coordinatePivotY
        )
    }

    // MARK: - Preview panel

    /// All preview panel work hops to the main thread: NSPanel ordering is
    /// main-thread-only, and the tap callback now runs on its own thread.
    /// Sequential dispatch preserves show/hide ordering.
    private func showPreview(_ appKitFrame: CGRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let previewPanel {
                previewPanel.setFrame(appKitFrame, display: true)
                return
            }
            let panel = SnapPreviewPanel(appKitFrame: appKitFrame)
            panel.orderFrontRegardless()
            previewPanel = panel
        }
    }

    private func hidePreview() {
        DispatchQueue.main.async { [weak self] in
            self?.previewPanel?.orderOut(nil)
            self?.previewPanel = nil
        }
    }

    /// Finds the snapshotted screen containing an AppKit global point,
    /// falling back to the first screen.
    private static func screen(containing point: CGPoint, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        screens.first { $0.frame.contains(point) } ?? screens.first
    }
}

/// Borderless, non-activating panel drawing the snap target preview: a
/// translucent accent rectangle with a rounded border.
final class SnapPreviewPanel: NSPanel {
    init(appKitFrame: CGRect) {
        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = SnapPreviewView(frame: NSRect(origin: .zero, size: appKitFrame.size))
    }
}

/// Draws the translucent snap target.
final class SnapPreviewView: NSView {
    override func draw(_: NSRect) {
        let accent = NSColor.controlAccentColor
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        accent.withAlphaComponent(0.18).setFill()
        path.fill()
        accent.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
