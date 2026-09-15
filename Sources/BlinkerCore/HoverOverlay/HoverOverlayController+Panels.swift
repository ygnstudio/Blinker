import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Panels and dwell (main thread only)

extension HoverOverlayController {
    func syncPanels(layout: OverlayLayout, hoveredIndex: Int?, settings: HoverOverlaySettings) {
        let signature = layout.buttons.map(\.frame)
        let pid = layout.target.hit.processIdentifier
        isOverlayVisible = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let needsRebuild = signature != panelSignature || pid != panelPID
                || panels.count != layout.buttons.count
                || extraPanels.count != layout.extraActions.count
                || layout.extraActions != panelExtraActions
            if needsRebuild {
                rebuildPanels(
                    layout: layout,
                    isHotspot: settings.mode == .hotspot,
                    glassTint: GlassTint.resolved(hex: settings.glassTintColorHex)
                )
            } else {
                // The tray is fronted before the panels so the enlarged
                // chips always stack above it (belt and braces: the tray
                // also sits one window level below the chips).
                trayPanel?.orderFrontRegardless()
                panels.forEach { $0.orderFrontRegardless() }
                extraPanels.forEach { $0.orderFrontRegardless() }
            }
            applyHoverTransition(
                hoveredIndex: hoveredIndex,
                dwellMilliseconds: settings.effectiveDwellMilliseconds
            )
        }
    }

    private func rebuildPanels(
        layout: OverlayLayout,
        isHotspot: Bool,
        glassTint: NSColor?
    ) {
        hidePanels()
        installTrayPanel(layout: layout, isHotspot: isHotspot, glassTint: glassTint)
        panels = zip(layout.buttons, layout.panelFrames).map { info, panelFrame in
            HoverOverlayPanel(
                panelFrame: panelFrame,
                info: info,
                isHotspot: isHotspot,
                onActivate: { [weak self] variant in
                    self?.activate(
                        info: info,
                        axWindow: layout.axWindow,
                        processIdentifier: layout.target.hit.processIdentifier,
                        bundleIdentifier: layout.target.bundleIdentifier,
                        variant: variant
                    )
                },
                onLongPress: { [weak self] in
                    self?.activateLongPress(
                        axWindow: layout.axWindow,
                        processIdentifier: layout.target.hit.processIdentifier,
                        bundleIdentifier: layout.target.bundleIdentifier,
                        button: info.button
                    )
                }
            )
        }
        panelSignature = layout.buttons.map(\.frame)
        panelPID = layout.target.hit.processIdentifier
        panelExtraActions = layout.extraActions
        extraPanels = layout.extraActions.enumerated().map { index, action in
            HoverOverlayExtraPanel(
                panelFrame: layout.extraPanelFrames[index],
                action: action,
                tintColor: glassTint
            ) { [weak self] in
                self?.activateExtra(ExtraChipContext(
                    action: action,
                    axWindow: layout.axWindow,
                    processIdentifier: layout.target.hit.processIdentifier,
                    anchorFrame: layout.extraPanelFrames[index],
                    buttonFrames: layout.buttons.map(\.frame),
                    windowBounds: layout.target.hit.bounds,
                    appName: layout.target.appName
                ))
            }
        }
        panels.forEach { $0.orderFrontRegardless() }
        extraPanels.forEach { $0.orderFrontRegardless() }
    }

    /// Installs the glass capsule tray behind the whole displayed group
    /// (enlarged traffic dots and extra chips). It goes in first so the
    /// chips stack above it; each traffic dot additionally gets a bounded
    /// radial glow on the glass that absorbs the native button's blurred
    /// ghost. Hotspot mode keeps the title bar untouched.
    private func installTrayPanel(
        layout: OverlayLayout,
        isHotspot: Bool,
        glassTint: NSColor?
    ) {
        guard !isHotspot else { return }
        guard
            let trayFrame = HoverOverlayTrayPanel.frame(
                forDisplayFrames: layout.allPanelFrames
            )
        else { return }
        let glows = zip(layout.buttons, layout.panelFrames).map { info, panelFrame in
            // The dot's circle rect (same inset rule as the chip drawing)
            // expressed in tray-local coordinates.
            let circleFrame = panelFrame.insetBy(dx: 4, dy: 4)
            return HoverOverlayTrayPanel.Glow(
                rect: HoverOverlayTrayPanel.localRect(
                    forAXRect: circleFrame,
                    inTray: trayFrame
                ),
                color: OverlayChipDrawing.vividColor(for: info.button)
            )
        }
        let tray = HoverOverlayTrayPanel(trayFrame: trayFrame, glows: glows, tintColor: glassTint)
        tray.orderFrontRegardless()
        trayPanel = tray
    }

    func hidePanels() {
        closeHUD()
        stopDwell()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        extraPanels.forEach { $0.orderOut(nil) }
        extraPanels = []
        panelExtraActions = []
        trayPanel?.orderOut(nil)
        trayPanel = nil
        panelSignature = []
        panelPID = 0
    }

    /// Performs the rule action (or a native AXPress when no rule applies)
    /// and hides the overlay. Runs on the main thread.
    private func activate(
        info: OverlayButtonInfo,
        axWindow: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        variant: ClickVariant
    ) {
        let summary = "\(info.axSubrole) as \(String(describing: variant))"
        logger.info("overlay button activated: \(summary, privacy: .public)")
        let action = bundleIdentifier.flatMap {
            ruleEngine.action(forBundleIdentifier: $0, button: info.button, variant: variant)
        }
        switch (action, variant) {
        case let (.some(action), _):
            workQueue.async { [actionPerformer] in
                actionPerformer.perform(
                    action,
                    button: info.button,
                    window: axWindow,
                    processIdentifier: processIdentifier
                )
            }
        case (.none, .left):
            workQueue.async { [weak self] in
                // The click was swallowed by the panel; log a failed press so
                // the user's dead click is at least diagnosable.
                if !AXQuery.pressButton(subrole: info.axSubrole, in: axWindow) {
                    self?.logger.error(
                        "native AXPress failed for \(info.axSubrole, privacy: .public); click was consumed"
                    )
                }
            }
        case (.none, _):
            // Unconfigured enhanced variant: nothing to do (the click is
            // already consumed by the enlarged panel), just stand down.
            logger.debug("no action configured for this variant; standing down")
        }
        // Deferred so the view survives the ongoing mouseDown dispatch.
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    /// Fires the long-press slot of a button (no-op when unconfigured).
    private func activateLongPress(
        axWindow: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        button: TrafficButton
    ) {
        guard
            let action = bundleIdentifier.flatMap({
                ruleEngine.action(forBundleIdentifier: $0, button: button, variant: .longPressLeft)
            })
        else {
            logger.debug("long press not configured; standing down")
            return
        }
        logger.info("overlay long press activated: \(String(describing: action), privacy: .public)")
        workQueue.async { [actionPerformer] in
            actionPerformer.perform(
                action,
                button: button,
                window: axWindow,
                processIdentifier: processIdentifier
            )
        }
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    /// Performs an extra chip's configured action and hides the overlay.
    /// The management chip opens the HUD instead (and keeps the overlay up).
    /// Runs on the main thread.
    private func activateExtra(_ context: ExtraChipContext) {
        let actionName = String(describing: context.action)
        logger.info("extra chip activated: \(actionName, privacy: .public)")
        if context.action == .windowManagerPanel {
            openHUD(context)
            return
        }
        workQueue.async { [actionPerformer] in
            actionPerformer.perform(
                context.action,
                button: .zoom,
                window: context.axWindow,
                processIdentifier: context.processIdentifier
            )
        }
        // Deferred so the view survives the ongoing mouseDown dispatch.
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    // MARK: - Management HUD

    /// The placement grid shown in the HUD, in reading order.
    private static let hudPlacements: [ButtonAction] = [
        .tileTopLeft, .tileTop, .tileTopRight,
        .tileLeft, .centerWindow, .tileRight,
        .tileBottomLeft, .tileBottom, .tileBottomRight,
        .maximize, .almostMaximize, .moveToNextDisplay,
    ]

    /// Opens the management HUD below the enlarged group. All actions act on
    /// the hovered window (`axWindow`) — never on the frontmost one.
    private func openHUD(_ context: ExtraChipContext) {
        closeHUD()

        let width: CGFloat = 252
        let workspaces = workspacesProvider()
        let gridRows = CGFloat(Self.hudPlacements.count / 3)
        let height = 18 + 10 + gridRows * 54 + 12 + CGFloat(min(workspaces.count, 6)) * 26 + 24

        // Anchor below the triggering chip, clamped into the window ∩ screen
        // container so the HUD never drifts off-screen.
        let container = Self.overlayContainerBounds(
            forButtonFrames: context.buttonFrames,
            windowBounds: context.windowBounds
        ) ?? context.windowBounds
        var originX = context.anchorFrame.minX
        originX = min(max(originX, container.minX + 4), container.maxX - width - 4)
        var originY = context.anchorFrame.maxY + 6
        originY = min(originY, container.maxY - height - 4)

        let axFrame = CGRect(x: originX, y: originY, width: width, height: height)
        let content = HoverOverlayHUDContent(
            appName: context.appName,
            placements: Self.hudPlacements,
            workspaces: workspaces,
            onAction: { [weak self] action in
                guard let self else { return }
                workQueue.async { [actionPerformer] in
                    actionPerformer.perform(
                        action,
                        button: .zoom,
                        window: context.axWindow,
                        processIdentifier: context.processIdentifier
                    )
                }
                closeHUD()
            },
            onRestore: { [weak self] id in
                guard let self else { return }
                workspaceRestorer(id)
                closeHUD()
            },
            onClose: { [weak self] in
                self?.closeHUD()
            }
        )
        hudPanel = HoverOverlayHUDPanel(
            axFrame: axFrame,
            content: content,
            tintColor: GlassTint.resolved(hex: settingsStore.snapshot.glassTintColorHex)
        )
        hudPanel?.orderFrontRegardless()
        hudStateLock.withLock {
            hudKeepAliveFrameAX = axFrame
            hudAnchorFrameAX = context.anchorFrame
        }
        logger.info("management HUD opened")
    }

    /// Closes the management HUD (idempotent).
    func closeHUD() {
        hudStateLock.withLock {
            hudKeepAliveFrameAX = .null
            hudAnchorFrameAX = .null
        }
        hudPanel?.orderOut(nil)
        hudPanel = nil
    }

    // MARK: - Dwell

    /// All dwell-capable chips, in display order (traffic lights, then the
    /// extra action chips).
    private var allDwellPanels: [any OverlayDwellPanel] {
        panels + extraPanels
    }

    /// Applies a hover transition: resets the previous panel's dwell and
    /// starts (or skips, when dwell is 0 ms) dwell on the newly hovered one.
    private func applyHoverTransition(hoveredIndex: Int?, dwellMilliseconds: Int) {
        let dwellPanels = allDwellPanels
        guard let index = hoveredIndex, dwellPanels.indices.contains(index) else {
            stopDwell()
            return
        }
        let panel = dwellPanels[index]
        guard panel !== hoveredPanel else { return }
        hoveredPanel?.resetDwell()
        hoveredPanel = panel
        activeDwellMilliseconds = dwellMilliseconds
        dwellStartedAt = Date()
        if dwellMilliseconds <= 0 {
            panel.setDwellProgress(1)
            stopDwellTimer()
        } else {
            startDwellTimer()
        }
    }

    func stopDwell() {
        hoveredPanel?.resetDwell()
        hoveredPanel = nil
        dwellStartedAt = nil
        stopDwellTimer()
    }

    private func startDwellTimer() {
        stopDwellTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            tickDwell()
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func stopDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    private func tickDwell() {
        guard let panel = hoveredPanel, let start = dwellStartedAt else { return }
        let elapsedMilliseconds = Date().timeIntervalSince(start) * 1000
        let progress = HoverOverlayGeometry.dwellProgress(
            elapsedMilliseconds: elapsedMilliseconds,
            dwellMilliseconds: activeDwellMilliseconds
        )
        panel.setDwellProgress(progress)
        if progress >= 1 {
            stopDwellTimer()
        }
    }

    // MARK: - Workspace observation

    /// Any app activation change hides the overlay; the next mouse move
    /// re-creates it when still hovering a title bar.
    func observeWorkspaceActivation() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanels()
        }
    }
}

/// Everything an extra-chip click needs: which action it maps to and the
/// hovered window it should act on (plus HUD anchoring geometry).
struct ExtraChipContext {
    let action: ButtonAction
    let axWindow: AXUIElement
    let processIdentifier: pid_t
    let anchorFrame: CGRect
    let buttonFrames: [CGRect]
    let windowBounds: CGRect
    let appName: String?
}
