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
                || panelMaskStyle != settings.maskStyle
            if needsRebuild {
                rebuildPanels(
                    layout: layout,
                    isHotspot: settings.mode == .hotspot,
                    maskStyle: settings.maskStyle
                )
            } else {
                // The mask is fronted before the panels so the enlarged
                // chips always stack above it (belt and braces: the mask
                // also sits one window level below the chips).
                maskPanel?.orderFrontRegardless()
                panels.forEach { $0.orderFrontRegardless() }
                extraPanels.forEach { $0.orderFrontRegardless() }
            }
            applyHoverTransition(
                hoveredIndex: hoveredIndex,
                dwellMilliseconds: settings.effectiveDwellMilliseconds
            )
        }
    }

    private func rebuildPanels(layout: OverlayLayout, isHotspot: Bool, maskStyle: HoverOverlayMaskStyle) {
        hidePanels()
        // The mask goes in first so the enlarged chips stack above it; it
        // hides the small native buttons peeking between the chips. In
        // sampled mode it shows the host title bar itself; without sampling
        // (no permission, no clean strip) it falls back to glass.
        if !isHotspot {
            let buttonFrames = layout.buttons.map(\.frame)
            if let maskFrame = HoverOverlayMaskPanel.frame(forButtonFrames: buttonFrames) {
                let mask = HoverOverlayMaskPanel(maskFrame: maskFrame)
                mask.orderFrontRegardless()
                maskPanel = mask
                if maskStyle == .sampled {
                    scheduleSampledBackdrop(
                        hit: layout.target.hit,
                        maskFrame: maskFrame,
                        buttonFrames: buttonFrames
                    )
                }
            }
        }
        panels = zip(layout.buttons, layout.panelFrames).map { info, panelFrame in
            HoverOverlayPanel(
                panelFrame: panelFrame,
                info: info,
                isHotspot: isHotspot
            ) { [weak self] in
                self?.activate(
                    info: info,
                    axWindow: layout.axWindow,
                    processIdentifier: layout.target.hit.processIdentifier,
                    bundleIdentifier: layout.target.bundleIdentifier
                )
            }
        }
        panelSignature = layout.buttons.map(\.frame)
        panelPID = layout.target.hit.processIdentifier
        panelMaskStyle = maskStyle
        panelExtraActions = layout.extraActions
        extraPanels = layout.extraActions.enumerated().map { index, action in
            HoverOverlayExtraPanel(
                panelFrame: layout.extraPanelFrames[index],
                action: action
            ) { [weak self] in
                self?.activateExtra(
                    action,
                    axWindow: layout.axWindow,
                    processIdentifier: layout.target.hit.processIdentifier
                )
            }
        }
        panels.forEach { $0.orderFrontRegardless() }
        extraPanels.forEach { $0.orderFrontRegardless() }
    }

    /// Kicks off the async title-bar sampling and swaps the mask to the
    /// sampled backdrop when it lands. Guards against staleness: if the
    /// overlay moved on to another window or was hidden meanwhile, the
    /// image is discarded.
    private func scheduleSampledBackdrop(
        hit: AXQuery.WindowHit,
        maskFrame: CGRect,
        buttonFrames: [CGRect]
    ) {
        guard hit.windowID != 0 else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task(priority: .userInitiated) { [weak self] in
            let image = await TitlebarSampler.maskImage(
                windowID: hit.windowID,
                windowBounds: hit.bounds,
                maskFrame: maskFrame,
                scale: scale
            )
            guard let image else { return }
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    isOverlayVisible,
                    panelPID == hit.processIdentifier,
                    panelSignature == buttonFrames,
                    let maskPanel
                else { return }
                maskPanel.setSampledImage(image)
            }
        }
    }

    func hidePanels() {
        stopDwell()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        extraPanels.forEach { $0.orderOut(nil) }
        extraPanels = []
        panelExtraActions = []
        maskPanel?.orderOut(nil)
        maskPanel = nil
        panelSignature = []
        panelPID = 0
        // Force a fresh rebuild (and re-sample) on the next show, since the
        // host title bar content may have changed while hidden.
        panelMaskStyle = nil
    }

    /// Performs the rule action (or a native AXPress when no rule applies)
    /// and hides the overlay. Runs on the main thread.
    private func activate(
        info: OverlayButtonInfo,
        axWindow: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String?
    ) {
        logger.info("overlay button activated: \(info.axSubrole, privacy: .public)")
        if let action = bundleIdentifier.flatMap({ ruleEngine.action(
            forBundleIdentifier: $0,
            button: info.button
        ) }) {
            workQueue.async { [actionPerformer] in
                actionPerformer.perform(
                    action,
                    button: info.button,
                    window: axWindow,
                    processIdentifier: processIdentifier
                )
            }
        } else {
            workQueue.async { [weak self] in
                // The click was swallowed by the panel; log a failed press so
                // the user's dead click is at least diagnosable.
                if !AXQuery.pressButton(subrole: info.axSubrole, in: axWindow) {
                    self?.logger.error(
                        "native AXPress failed for \(info.axSubrole, privacy: .public); click was consumed"
                    )
                }
            }
        }
        // Deferred so the view survives the ongoing mouseDown dispatch.
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
    }

    /// Performs an extra chip's configured action and hides the overlay.
    /// Runs on the main thread.
    private func activateExtra(
        _ action: ButtonAction,
        axWindow: AXUIElement,
        processIdentifier: pid_t
    ) {
        logger.info("extra chip activated: \(String(describing: action), privacy: .public)")
        workQueue.async { [actionPerformer] in
            actionPerformer.perform(
                action,
                button: .zoom,
                window: axWindow,
                processIdentifier: processIdentifier
            )
        }
        // Deferred so the view survives the ongoing mouseDown dispatch.
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
        }
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
