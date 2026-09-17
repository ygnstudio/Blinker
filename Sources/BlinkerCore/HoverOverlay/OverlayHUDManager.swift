import AppKit
import ApplicationServices
import os

/// Owns the management HUD: the panel, its keep-alive geometry and the
/// safe-corridor gate. The frame state is read from the work queue's cursor
/// detection while the main thread opens/closes the HUD, hence the lock.
final class OverlayHUDManager {
    /// The open management HUD, if any. Main-thread owned.
    private var panel: HoverOverlayHUDPanel?
    /// Guards the keep-alive frame below, read from the work queue's cursor
    /// detection while the main thread opens/closes the HUD.
    private let stateLock = NSLock()
    private var keepAliveFrameAX: CGRect = .null
    /// The chip frame that opened the HUD; anchors the safe corridor.
    private var anchorFrameAX: CGRect = .null

    private let workspacesProvider: () -> [HUDWorkspaceItem]
    private let workspaceRestorer: (UUID) -> Void
    private let actionPerformer: WindowActionPerforming
    private let workQueue: DispatchQueue
    private let logger: Logger

    init(
        workspacesProvider: @escaping () -> [HUDWorkspaceItem],
        workspaceRestorer: @escaping (UUID) -> Void,
        actionPerformer: WindowActionPerforming,
        workQueue: DispatchQueue,
        logger: Logger
    ) {
        self.workspacesProvider = workspacesProvider
        self.workspaceRestorer = workspaceRestorer
        self.actionPerformer = actionPerformer
        self.workQueue = workQueue
        self.logger = logger
    }

    /// Whether the cursor is inside the open HUD or the safe corridor
    /// between the HUD and the chip that opened it (work-queue safe).
    /// Inside this zone the HUD stays open while the cursor travels from
    /// the chip to the panel.
    func safeZoneContains(_ point: CGPoint) -> Bool {
        stateLock.withLock {
            guard !keepAliveFrameAX.isNull else { return false }
            if keepAliveFrameAX.contains(point) {
                return true
            }
            guard !anchorFrameAX.isNull else { return false }
            // Still hovering the chip that opened the HUD: safe.
            if anchorFrameAX.contains(point) {
                return true
            }
            return HoverOverlayGeometry.safeCorridorContains(
                cursor: point,
                anchor: anchorFrameAX,
                panel: keepAliveFrameAX
            )
        }
    }

    var isOpen: Bool {
        stateLock.withLock { !keepAliveFrameAX.isNull }
    }

    /// The placement grid shown in the HUD, in reading order.
    private static let placements: [ButtonAction] = [
        .tileTopLeft, .tileTop, .tileTopRight,
        .tileLeft, .centerWindow, .tileRight,
        .tileBottomLeft, .tileBottom, .tileBottomRight,
        .maximize, .almostMaximize, .moveToNextDisplay,
    ]

    /// Opens the management HUD below the enlarged group. All actions act on
    /// the hovered window (`axWindow`) — never on the frontmost one. The
    /// panel measures its own size from the SwiftUI content; this method
    /// only anchors and clamps the position.
    func open(_ context: ExtraChipContext) {
        close()

        let content = makeContent(context)
        // The HUD panel is kept alive across open/close cycles: a reused
        // window carries its established glass blend, so later opens come up
        // instantly clean. Only the very first one still fades in.
        let hudPanel: HoverOverlayHUDPanel
        if let existing = panel {
            existing.update(content: content, axOrigin: anchorOrigin(context))
            hudPanel = existing
        } else {
            hudPanel = HoverOverlayHUDPanel(
                axOrigin: anchorOrigin(context),
                content: content
            )
            panel = hudPanel
        }

        let frame = clampedFrame(of: hudPanel, in: context)
        hudPanel.setAXFrame(frame)

        if hudPanel.alphaValue < 1 {
            // A first fade that was cut short by a quick close can leave the
            // window at zero alpha; restart the fade rather than showing an
            // invisible (or half-blended) HUD.
            hudPanel.orderFrontFadingIn()
        } else {
            hudPanel.orderFrontRegardless()
        }
        stateLock.withLock {
            keepAliveFrameAX = frame
            anchorFrameAX = context.anchorFrame
        }
        logger.info("management HUD opened")
    }

    /// The HUD's top-left origin, six points below the anchor chip.
    private func anchorOrigin(_ context: ExtraChipContext) -> CGPoint {
        CGPoint(x: context.anchorFrame.minX, y: context.anchorFrame.maxY + 6)
    }

    /// Builds the HUD's SwiftUI content with all action wiring.
    private func makeContent(_ context: ExtraChipContext) -> HoverOverlayHUDContent {
        HoverOverlayHUDContent(
            appName: context.appName,
            placements: Self.placements,
            workspaces: workspacesProvider(),
            onAction: { [weak self] action in
                guard let self else { return }
                workQueue.async { [actionPerformer] in
                    actionPerformer.perform(
                        action,
                        window: context.axWindow,
                        processIdentifier: context.processIdentifier
                    )
                }
                close()
            },
            onRestore: { [weak self] id in
                guard let self else { return }
                workspaceRestorer(id)
                close()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
    }

    /// Clamps the measured frame into the window ∩ screen container so the
    /// HUD never drifts off-screen.
    private func clampedFrame(
        of hudPanel: HoverOverlayHUDPanel,
        in context: ExtraChipContext
    ) -> CGRect {
        let container = HoverOverlayController.overlayContainerBounds(
            forButtonFrames: context.buttonFrames,
            windowBounds: context.windowBounds
        ) ?? context.windowBounds
        var frame = hudPanel.axFrame
        frame.origin.x = min(max(frame.minX, container.minX + 4), container.maxX - frame.width - 4)
        frame.origin.y = min(frame.minY, container.maxY - frame.height - 4)
        return frame
    }

    /// Closes the management HUD (idempotent). The panel is only hidden,
    /// never released: keeping it alive preserves the glass blend so the
    /// next open is flash-free.
    func close() {
        stateLock.withLock {
            keepAliveFrameAX = .null
            anchorFrameAX = .null
        }
        panel?.orderOut(nil)
    }
}
