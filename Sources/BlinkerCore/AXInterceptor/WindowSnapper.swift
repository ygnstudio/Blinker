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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "snapper")

    private static let titleBarBandHeight: CGFloat = 32
    /// Guards the mutable drag state below (tap callback runs on the main
    /// run loop; `isEnabled` is toggled from the settings UI).
    private let stateLock = NSLock()
    private var isEnabled = true
    private var drag: DragContext?

    /// Bookkeeping for one window drag, from mouse down to mouse up.
    private struct DragContext {
        let processIdentifier: pid_t
        /// The window's `CGWindowList` bounds at drag start (used to resolve
        /// the AX window; resolution falls back to the app's focused window,
        /// which is correct mid-drag).
        let initialBounds: CGRect
        /// The placement currently previewed, if any.
        var previewedPlacement: WindowPlacement?
    }

    private var previewPanel: SnapPreviewPanel?

    public init(actionPerformer: WindowActionPerforming) {
        self.actionPerformer = actionPerformer
    }

    public var isRunning: Bool {
        eventTap != nil
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
        guard eventTap == nil else { return true }
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
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            logger.error("CGEvent.tapCreate returned nil (snapper, listenOnly)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        logger.info("snapper tap installed (observe-only)")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        hidePreview()
    }

    deinit {
        stop()
    }

    // MARK: - Event handling

    private func handle(event: CGEvent, eventType: CGEventType) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        switch eventType {
        case .leftMouseDown:
            handleDragStart(at: event.location)
        case .leftMouseDragged:
            handleDragMove(to: event.location)
        case .leftMouseUp:
            handleDragEnd(at: event.location)
        default:
            break
        }
    }

    /// Arms the drag context when a mouse down could start a window drag.
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

        stateLock.lock()
        drag = DragContext(
            processIdentifier: hit.processIdentifier,
            initialBounds: hit.bounds,
            previewedPlacement: nil
        )
        stateLock.unlock()
    }

    private func handleDragMove(to location: CGPoint) {
        stateLock.lock()
        guard drag != nil, isEnabled else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let screen = Self.screen(containing: location) else { return }
        let visibleFrame = screen.visibleFrame
        guard let placement = SnapZones.placement(at: location, in: visibleFrame) else {
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

    private func handleDragEnd(at location: CGPoint) {
        stateLock.lock()
        let context = drag
        drag = nil
        stateLock.unlock()
        hidePreview()

        guard let context, let placement = context.previewedPlacement else { return }
        guard let screen = Self.screen(containing: location) else { return }
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
            globalMaxY: NSScreen.screens.first?.frame.maxY ?? 0
        )
    }

    // MARK: - Preview panel

    private func showPreview(_ appKitFrame: CGRect) {
        if let previewPanel {
            previewPanel.setFrame(appKitFrame, display: true)
            return
        }
        let panel = SnapPreviewPanel(appKitFrame: appKitFrame)
        panel.orderFrontRegardless()
        previewPanel = panel
    }

    private func hidePreview() {
        previewPanel?.orderOut(nil)
        previewPanel = nil
    }

    /// Finds the screen containing a global point, falling back to the main
    /// screen.
    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
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
