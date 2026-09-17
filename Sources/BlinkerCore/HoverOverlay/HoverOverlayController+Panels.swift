import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Panels and activation (main thread only)

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
                    isHotspot: settings.mode == .hotspot
                )
            } else {
                // The tray is fronted before the panels so the enlarged
                // chips always stack above it (belt and braces: the tray
                // also sits one window level below the chips).
                trayPanel?.orderFrontRegardless()
                panels.forEach { $0.orderFrontRegardless() }
                extraPanels.forEach { $0.orderFrontRegardless() }
            }
            dwell.applyHoverTransition(
                dwellPanels: allDwellPanels,
                hoveredIndex: hoveredIndex,
                dwellMilliseconds: settings.effectiveDwellMilliseconds
            )
        }
    }

    private func rebuildPanels(layout: OverlayLayout, isHotspot: Bool) {
        hidePanels()
        installTrayPanel(layout: layout, isHotspot: isHotspot)
        panels = makeTrafficPanels(layout: layout, isHotspot: isHotspot)
        panelSignature = layout.buttons.map(\.frame)
        panelPID = layout.target.hit.processIdentifier
        panelExtraActions = layout.extraActions
        extraPanels = makeExtraPanels(layout: layout)
        panels.forEach { $0.orderFrontRegardless() }
        extraPanels.forEach { $0.orderFrontRegardless() }
    }

    /// One enlarged-button panel per traffic light, with a long-press probe
    /// wired to the rule engine. Value-captured engine so the probe closure
    /// stays Sendable and never retains the controller.
    private func makeTrafficPanels(layout: OverlayLayout, isHotspot: Bool) -> [HoverOverlayPanel] {
        let ruleEngine = self.ruleEngine
        let bundleIdentifier = layout.target.bundleIdentifier
        return zip(layout.buttons, layout.panelFrames).map { info, panelFrame in
            HoverOverlayPanel(
                panelFrame: panelFrame,
                info: info,
                isHotspot: isHotspot,
                hasLongPressAction: {
                    ruleEngine.action(
                        forBundleIdentifier: bundleIdentifier,
                        button: info.button,
                        variant: .longPressLeft
                    ) != nil
                },
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
    }

    /// One non-activating chip panel per configured extra action.
    private func makeExtraPanels(layout: OverlayLayout) -> [HoverOverlayExtraPanel] {
        layout.extraActions.enumerated().map { index, action in
            HoverOverlayExtraPanel(
                panelFrame: layout.extraPanelFrames[index],
                action: action
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
    }

    /// Installs the glass capsule tray behind the whole displayed group
    /// (enlarged traffic dots and extra chips). It goes in first so the
    /// chips stack above it; each traffic dot additionally gets a bounded
    /// radial glow on the glass that absorbs the native button's blurred
    /// ghost. Hotspot mode keeps the title bar untouched.
    private func installTrayPanel(layout: OverlayLayout, isHotspot: Bool) {
        guard !isHotspot else { return }
        guard
            let trayFrame = HoverOverlayTrayPanel.frame(
                forDisplayFrames: layout.allPanelFrames
            )
        else { return }
        let glows = zip(layout.buttons, layout.panelFrames).map { info, panelFrame in
            // The dot's circle rect (same inset rule as the chip drawing)
            // expressed in tray-local coordinates.
            let circleFrame = panelFrame.insetBy(
                dx: OverlayChipDrawing.chipInset,
                dy: OverlayChipDrawing.chipInset
            )
            return HoverOverlayTrayPanel.Glow(
                rect: HoverOverlayTrayPanel.localRect(
                    forAXRect: circleFrame,
                    inTray: trayFrame
                ),
                color: OverlayChipDrawing.vividColor(for: info.button)
            )
        }
        // The tray is kept alive across hide/show cycles: a reused window
        // carries its established glass blend, so later appearances come up
        // clean instead of replaying the unblended-base flash. Only the
        // very first tray still needs the two-phase fade.
        if let tray = trayPanel {
            tray.update(trayFrame: trayFrame, glows: glows)
            if tray.needsGlassFade {
                // A first glass fade that was cut short by a quick
                // hover-out can leave the backdrop at zero alpha; restart
                // it rather than showing a glow-only (or half-blended)
                // tray.
                tray.orderFrontFadingIn()
            } else {
                tray.orderFrontRegardless()
            }
        } else {
            let tray = HoverOverlayTrayPanel(trayFrame: trayFrame, glows: glows)
            tray.orderFrontFadingIn()
            trayPanel = tray
        }
    }

    func hidePanels() {
        hud.close()
        dwell.stop()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        extraPanels.forEach { $0.orderOut(nil) }
        extraPanels = []
        panelExtraActions = []
        // The tray window is only hidden, never released: keeping it alive
        // preserves the glass blend so the next appearance is flash-free.
        trayPanel?.orderOut(nil)
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
                    window: axWindow,
                    processIdentifier: processIdentifier
                )
            }
        case (nil, .left):
            workQueue.async { [weak self] in
                // The click was swallowed by the panel; log a failed press so
                // the user's dead click is at least diagnosable.
                if !AXQuery.pressButton(subrole: info.axSubrole, in: axWindow) {
                    self?.logger.error(
                        "native AXPress failed for \(info.axSubrole, privacy: .public); click was consumed"
                    )
                }
            }
        case (nil, _):
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
            hud.open(context)
            return
        }
        workQueue.async { [actionPerformer] in
            actionPerformer.perform(
                context.action,
                window: context.axWindow,
                processIdentifier: context.processIdentifier
            )
        }
        // Deferred so the view survives the ongoing mouseDown dispatch.
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    /// All dwell-capable chips, in display order (traffic lights, then the
    /// extra action chips).
    private var allDwellPanels: [any OverlayDwellPanel] {
        panels + extraPanels
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
