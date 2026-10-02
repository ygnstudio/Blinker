import AppKit
import ApplicationServices
import CoreGraphics

struct OverlayPresentation {
    let layout: OverlayLayout
    let hoveredIndex: Int?
    let settings: HoverOverlaySettings
}

extension HoverOverlayController {
    func syncPanels(
        layout: OverlayLayout, hoveredIndex: Int?, settings: HoverOverlaySettings, revision: UInt64
    ) {
        let presentation = OverlayPresentation(
            layout: layout, hoveredIndex: hoveredIndex, settings: settings
        )
        guard presentationState.submit(presentation, revision: revision) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let pending = presentationState.takePending(), tapHost.isRunning,
                  presentationState.isCurrent(pending.revision) else { return }
            let presentation = pending.presentation
            let layout = presentation.layout
            let settings = presentation.settings
            let needsRebuild = layout.allPanelFrames != panelSignature
                || layout.target.hit.windowID != panelWindowID
                || layout.target.hit.processIdentifier != panelPID
                || layout.extraActions != panelExtraActions
                || panels.isEmpty
            if needsRebuild {
                rebuildPanels(layout: layout)
            }
            guard presentationState.publish(layout, revision: pending.revision) else {
                removePanelViews()
                return
            }
            updateButtonPresentations(layout: layout, settings: settings)
            // An already-visible window needs no ordering call on mouse moves.
            dwell.applyHoverTransition(
                dwellPanels: allDwellPanels,
                hoveredIndex: presentation.hoveredIndex,
                dwellMilliseconds: settings.dwellMilliseconds
            )
        }
    }

    private func rebuildPanels(layout: OverlayLayout) {
        removePanelViews()
        panels = makeTrafficButtons(layout: layout)
        extraPanels = makeExtraButtons(layout: layout)
        let controls = panels + extraPanels
        if let frame = HoverOverlayTrayPanel.frame(forDisplayFrames: layout.allPanelFrames) {
            OverlayClickGate.setOverlayFrames([frame])
            let tray = trayPanel ?? HoverOverlayTrayPanel(trayFrame: frame)
            tray.update(trayFrame: frame, controls: controls, frames: layout.allPanelFrames)
            trayPanel = tray
            tray.orderFrontRegardless()
        }
        panelSignature = layout.allPanelFrames
        panelWindowID = layout.target.hit.windowID
        panelPID = layout.target.hit.processIdentifier
        panelExtraActions = layout.extraActions
    }

    private func updateButtonPresentations(layout: OverlayLayout, settings: HoverOverlaySettings) {
        let variant = OverlayActionPresentation.variant(for: NSEvent.modifierFlags)
        for (control, info) in zip(panels, layout.buttons) {
            let resolve: (ClickVariant) -> OverlayActionPresentation = { [ruleEngine] variant in
                OverlayActionPresentation.resolve(engine: ruleEngine,
                                                  bundleID: layout.target.bundleIdentifier,
                                                  button: info.button, variant: variant)
            }
            control.updatePresentation(resolve(variant))
            control.requiresDwell = { !settings.protectQuitOnly || resolve($0).action == .quitApp }
        }
        for (control, action) in zip(extraPanels, layout.extraActions) {
            control.requiresDwell = { _ in !settings.protectQuitOnly || action == .quitApp }
        }
    }

    private func makeTrafficButtons(layout: OverlayLayout) -> [HoverOverlayButtonView] {
        zip(layout.buttons, layout.panelFrames).map { info, frame in
            let presentation = OverlayActionPresentation.resolve(
                engine: ruleEngine, bundleID: layout.target.bundleIdentifier, button: info.button,
                variant: .left
            )
            return HoverOverlayButtonView(
                frame: NSRect(origin: .zero, size: frame.size),
                symbol: presentation.symbol,
                label: presentation.label,
                color: OverlayChipDrawing.vividColor(for: info.button),
                hasLongPressAction: { [ruleEngine] in
                    ruleEngine.action(
                        forBundleIdentifier: layout.target.bundleIdentifier,
                        button: info.button, variant: .longPressLeft
                    ) != nil
                },
                onActivate: { [weak self] variant in
                    self?.activate(
                        info: info, axWindow: layout.axWindow,
                        processIdentifier: layout.target.hit.processIdentifier,
                        bundleIdentifier: layout.target.bundleIdentifier, variant: variant
                    )
                },
                onLongPress: { [weak self] in
                    self?.activateLongPress(
                        axWindow: layout.axWindow,
                        processIdentifier: layout.target.hit.processIdentifier,
                        bundleIdentifier: layout.target.bundleIdentifier, button: info.button
                    )
                }
            )
        }
    }

    private func makeExtraButtons(layout: OverlayLayout) -> [HoverOverlayButtonView] {
        layout.extraActions.enumerated().map { index, action in
            HoverOverlayButtonView(
                frame: NSRect(origin: .zero, size: layout.extraPanelFrames[index].size),
                symbol: action.extraSymbolName ?? "circle",
                label: action.localizedLabel, color: .controlAccentColor,
                onActivate: { [weak self] _ in
                    self?.activateExtra(ExtraChipContext(
                        action: action, axWindow: layout.axWindow,
                        processIdentifier: layout.target.hit.processIdentifier,
                        anchorFrame: layout.extraPanelFrames[index],
                        buttonFrames: layout.buttons.map(\.frame),
                        windowBounds: layout.target.hit.bounds, appName: layout.target.appName
                    ))
                }
            )
        }
    }

    func hidePanels() {
        presentationState.invalidate()
        removePanelViews()
    }

    func removePanelViews() {
        hud.close()
        dwell.stop()
        OverlayClickGate.setOverlayFrames([])
        trayPanel?.orderOut(nil)
        panels = []
        extraPanels = []
        panelExtraActions = []
        panelSignature = []
        panelWindowID = 0
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
            workQueue.async { [actionPerformer] in
                actionPerformer.pressNativeButton(
                    subrole: info.axSubrole,
                    window: axWindow,
                    processIdentifier: processIdentifier
                )
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
