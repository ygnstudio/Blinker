import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Panels and dwell (main thread only)

extension HoverOverlayController {
    func syncPanels(
        buttons: [OverlayButtonInfo],
        axWindow: AXUIElement,
        target: HoverTarget,
        hoveredIndex: Int?,
        panelFrames: [CGRect],
        settings: HoverOverlaySettings
    ) {
        let signature = buttons.map(\.frame)
        let pid = target.hit.processIdentifier
        isOverlayVisible = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if signature != panelSignature || pid != panelPID || panels.count != buttons.count {
                rebuildPanels(
                    buttons: buttons,
                    axWindow: axWindow,
                    target: target,
                    panelFrames: panelFrames,
                    isHotspot: settings.mode == .hotspot
                )
            } else {
                panels.forEach { $0.orderFrontRegardless() }
                maskPanel?.orderFrontRegardless()
            }
            applyHoverTransition(
                hoveredIndex: hoveredIndex,
                dwellMilliseconds: settings.effectiveDwellMilliseconds
            )
        }
    }

    private func rebuildPanels(
        buttons: [OverlayButtonInfo],
        axWindow: AXUIElement,
        target: HoverTarget,
        panelFrames: [CGRect],
        isHotspot: Bool
    ) {
        hidePanels()
        // The mask goes in first so the enlarged chips stack above it; it
        // hides the small native buttons peeking between the chips.
        if !isHotspot, let maskFrame = HoverOverlayMaskPanel.frame(forButtonFrames: buttons.map(\.frame)) {
            let mask = HoverOverlayMaskPanel(maskFrame: maskFrame)
            mask.orderFrontRegardless()
            maskPanel = mask
        }
        panels = zip(buttons, panelFrames).map { info, panelFrame in
            HoverOverlayPanel(
                panelFrame: panelFrame,
                info: info,
                isHotspot: isHotspot
            ) { [weak self] in
                self?.activate(
                    info: info,
                    axWindow: axWindow,
                    processIdentifier: target.hit.processIdentifier,
                    bundleIdentifier: target.bundleIdentifier
                )
            }
        }
        panelSignature = buttons.map(\.frame)
        panelPID = target.hit.processIdentifier
        panels.forEach { $0.orderFrontRegardless() }
    }

    func hidePanels() {
        stopDwell()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        maskPanel?.orderOut(nil)
        maskPanel = nil
        panelSignature = []
        panelPID = 0
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

    // MARK: - Dwell

    /// Applies a hover transition: resets the previous panel's dwell and
    /// starts (or skips, when dwell is 0 ms) dwell on the newly hovered one.
    private func applyHoverTransition(hoveredIndex: Int?, dwellMilliseconds: Int) {
        guard let index = hoveredIndex, panels.indices.contains(index) else {
            stopDwell()
            return
        }
        let panel = panels[index]
        guard panel !== hoveredPanel else { return }
        hoveredPanel?.buttonView.resetDwell()
        hoveredPanel = panel
        activeDwellMilliseconds = dwellMilliseconds
        dwellStartedAt = Date()
        if dwellMilliseconds <= 0 {
            panel.buttonView.setDwellProgress(1)
            stopDwellTimer()
        } else {
            startDwellTimer()
        }
    }

    func stopDwell() {
        hoveredPanel?.buttonView.resetDwell()
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
        panel.buttonView.setDwellProgress(progress)
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
