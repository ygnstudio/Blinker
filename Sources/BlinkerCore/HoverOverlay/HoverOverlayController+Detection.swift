import AppKit
import ApplicationServices
import CoreGraphics

/// The window currently under the cursor, with the identity information the
/// overlays need to resolve rules.
struct HoverTarget {
    let hit: AXQuery.WindowHit
    let bundleIdentifier: String
    let appName: String?
}

/// One detection pass's resolved overlay layout: the native buttons, the
/// window element to act on, the app identity, the enlarged panel frames and
/// the extra action chips appended after them.
struct OverlayLayout {
    let buttons: [OverlayButtonInfo]
    let axWindow: AXUIElement
    let target: HoverTarget
    let panelFrames: [CGRect]
    /// Actions of the extra chips, in display order (left to right, after
    /// the last traffic chip).
    let extraActions: [ButtonAction]
    /// Panel frames of the extra chips, aligned with `extraActions`.
    let extraPanelFrames: [CGRect]

    /// Every chip frame (traffic then extras); drives trigger-zone and
    /// hover hit-testing.
    var allPanelFrames: [CGRect] {
        panelFrames + extraPanelFrames
    }
}

// MARK: - Cursor tracking and AX detection (work queue only)

extension HoverOverlayController {
    func handleCursorMove(to location: CGPoint) {
        guard canDetectCursor else { return }
        // While the management HUD is open the overlay must not fight it:
        // inside the HUD — or the safe corridor between the HUD and the
        // chip that opened it — everything stays as-is; outside it the HUD
        // closes and normal detection resumes.
        if hud.isOpen {
            if hud.safeZoneContains(location) {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.hud.close()
            }
        }
        let revision = presentationState.revision
        let settings = settingsStore.snapshot
        guard settings.isEnabled else {
            resetDetectionAndHide()
            return
        }
        // Retain the visible palette's owner before asking what lies beneath
        // the pointer. Covering controls can extend beyond the owner's frame.
        if let layout = presentationState.displayedLayout(at: location) {
            guard AXQuery.isWindowCurrent(layout.target.hit),
                  HoverTestWindow.contains(layout.target.hit)
                  || ruleEngine.allowsHover(for: layout.target.bundleIdentifier,
                                            allWindows: settings.appliesToAllWindows) else {
                resetDetectionAndHide()
                return
            }
            syncPanels(
                layout: layout, hoveredIndex: hoveredIndex(at: location, in: layout),
                settings: settings, revision: revision
            )
            return
        }
        detectWakeTarget(at: location, settings: settings, revision: revision)
    }

    private func detectWakeTarget(
        at location: CGPoint, settings: HoverOverlaySettings, revision: UInt64
    ) {
        guard
            let hit = AXQuery.windowUnderPoint(
                location,
                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                includingTestWindow: true,
                // Check the cached window and all windows above it in z-order.
                usingCache: true
            ),
            let app = NSRunningApplication(processIdentifier: hit.processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else {
            resetDetectionAndHide()
            return
        }
        if !HoverTestWindow.contains(hit),
           !ruleEngine.allowsHover(for: bundleIdentifier, allWindows: settings.appliesToAllWindows) {
            resetDetectionAndHide()
            return
        }
        // Do not enumerate AX children for ordinary motion in a window's
        // content. A visible palette may extend below this title-bar band.
        if location.y - hit.bounds.minY > InterceptorMetrics.titleBarBandHeight {
            resetDetectionAndHide()
            return
        }
        let target = HoverTarget(hit: hit, bundleIdentifier: bundleIdentifier, appName: app.localizedName)

        let layout = resolveWindowLayout(
            windowHit: hit,
            target: target,
            settings: settings
        )
        guard let layout else {
            resetDetectionAndHide()
            return
        }
        guard HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: location, buttonFrames: layout.buttons.map(\.frame), panelFrames: [], trayFrame: nil
        ) else {
            resetDetectionAndHide()
            return
        }
        let key = "\(revision):\(hit.processIdentifier):\(hit.windowID):\(hit.bounds)"
        let remaining = wakeGate.remaining(for: key, now: ProcessInfo.processInfo.systemUptime,
                                           delayMilliseconds: settings.appearanceDelayMilliseconds)
        guard remaining <= 0 else {
            scheduleWakeCheck(after: remaining, revision: revision)
            return
        }
        syncPanels(layout: layout, hoveredIndex: hoveredIndex(at: location, in: layout),
                   settings: settings, revision: revision)
    }

    private func scheduleWakeCheck(after delay: TimeInterval, revision: UInt64) {
        wakeCheckRevision = revision
        guard !wakeCheckScheduled else { return }
        wakeCheckScheduled = true
        workQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            wakeCheckScheduled = false
            guard tapHost.isRunning, presentationState.isCurrent(wakeCheckRevision),
                  let point = CGEvent(source: nil)?.location else { return }
            handleCursorMove(to: point)
        }
    }

    private func hoveredIndex(at location: CGPoint, in layout: OverlayLayout) -> Int? {
        layout.allPanelFrames.firstIndex {
            HoverOverlayGeometry.isCursorInPanel(cursor: location, panelFrame: $0)
        }
    }

    /// Resolves the traffic buttons for the window under the cursor and lays
    /// out the enlarged controls and tray inside the window/screen intersection.
    /// Returns `nil` when there are no traffic buttons or no room for the tray.
    private func resolveWindowLayout(
        windowHit: AXQuery.WindowHit,
        target: HoverTarget,
        settings: HoverOverlaySettings
    ) -> OverlayLayout? {
        let resolved = resolveButtons(windowHit: windowHit)
        guard !resolved.buttons.isEmpty, let axWindow = resolved.axWindow else { return nil }
        let frames = resolved.buttons.map(\.frame)
        let extraActions = settings.enabledExtraActions
        guard let container = Self.overlayContainerBounds(
            forButtonFrames: frames, windowBounds: windowHit.bounds
        ) else { return nil }
        let allFrames = HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: frames,
            enlargedSize: settings.enlargedSize,
            containerBounds: container,
            extraCount: extraActions.count
        )
        let panelFrames = Array(allFrames.prefix(frames.count))
        guard allFrames.count == frames.count + extraActions.count else { return nil }
        let extraPanelFrames = Array(allFrames.dropFirst(frames.count))
        return OverlayLayout(
            buttons: resolved.buttons,
            axWindow: axWindow,
            target: target,
            panelFrames: panelFrames,
            extraActions: extraActions,
            extraPanelFrames: extraPanelFrames
        )
    }

    /// Returns the traffic buttons of the window under the cursor, re-reading
    /// them via AX only when the CG window identity changed (pid + window id
    /// + bounds — a same-pid same-frame window swap must not serve the
    /// closed window's zombie AX element) or the cache is empty; otherwise
    /// serves the cached values.
    private func resolveButtons(
        windowHit: AXQuery.WindowHit
    ) -> (buttons: [OverlayButtonInfo], axWindow: AXUIElement?) {
        let boundsUnchanged = !HoverOverlayGeometry.hasWindowBoundsChanged(
            previous: cachedWindowBounds,
            current: windowHit.bounds
        )
        if cachedWindowPID == windowHit.processIdentifier,
           cachedWindowID == windowHit.windowID,
           boundsUnchanged {
            return (cachedButtons, cachedAXWindow)
        }

        guard
            let axWindow = AXQuery.resolveWindow(
                processIdentifier: windowHit.processIdentifier,
                bounds: windowHit.bounds
            )
        else {
            cacheButtons([], axWindow: nil, hit: windowHit)
            return ([], nil)
        }
        let buttons = Self.readTrafficButtons(in: axWindow)
        cacheButtons(buttons, axWindow: axWindow, hit: windowHit)
        return (buttons, axWindow)
    }

    private func cacheButtons(
        _ buttons: [OverlayButtonInfo], axWindow: AXUIElement?, hit: AXQuery.WindowHit
    ) {
        cachedButtons = buttons
        cachedAXWindow = axWindow
        cachedWindowPID = hit.processIdentifier
        cachedWindowID = hit.windowID
        cachedWindowBounds = hit.bounds
    }

    func resetDetectionAndHide() {
        wakeGate.reset()
        cachedButtons = []
        cachedAXWindow = nil
        cachedWindowPID = 0
        cachedWindowID = 0
        cachedWindowBounds = nil
        let revision = presentationState.invalidate()
        DispatchQueue.main.async { [weak self] in
            guard let self, presentationState.shouldRemoveViews(revision: revision) else { return }
            removePanelViews()
        }
    }

    /// Reads the standard traffic-light buttons of a window via AX, ordered
    /// left to right.
    private static func readTrafficButtons(in window: AXUIElement) -> [OverlayButtonInfo] {
        AXQuery.applyMessagingTimeout(window)
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
            let children = childrenRef as? [AXUIElement]
        else { return [] }

        var buttons: [OverlayButtonInfo] = []
        for child in children {
            AXQuery.applyMessagingTimeout(child)
            guard
                let subrole = AXQuery.stringAttribute(child, kAXSubroleAttribute),
                let button = TrafficButton(axSubrole: subrole),
                let frame = AXQuery.elementFrame(child)
            else { continue }
            buttons.append(OverlayButtonInfo(button: button, axSubrole: subrole, frame: frame))
        }
        return buttons.sorted { $0.frame.minX < $1.frame.minX }
    }
}
