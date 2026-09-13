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

// MARK: - Cursor tracking and AX detection (work queue only)

extension HoverOverlayController {
    func handleCursorMove(to location: CGPoint) {
        let settings = settingsStore.snapshot
        guard settings.isEnabled, let target = allowedTarget(at: location, settings: settings) else {
            resetDetectionAndHide()
            return
        }

        let resolved = resolveButtons(windowHit: target.hit)
        guard !resolved.buttons.isEmpty, let axWindow = resolved.axWindow else {
            resetDetectionAndHide()
            return
        }

        let hoveredIndex = hoveredPanelIndex(
            cursor: location,
            buttons: resolved.buttons,
            enlargedSize: settings.enlargedSize
        )
        syncPanels(
            buttons: resolved.buttons,
            axWindow: axWindow,
            target: target,
            hoveredIndex: hoveredIndex,
            settings: settings
        )
    }

    /// Cheap pass/fail checks before any AX work: window under cursor, title
    /// bar band, and (when `appliesToAllWindows` is off) rule existence.
    private func allowedTarget(
        at location: CGPoint,
        settings: HoverOverlaySettings
    ) -> HoverTarget? {
        guard
            let hit = AXQuery.windowUnderPoint(
                location,
                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            HoverOverlayGeometry.isCursorInTitleBarBand(cursor: location, windowBounds: hit.bounds),
            let app = NSRunningApplication(processIdentifier: hit.processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else { return nil }
        if !settings.appliesToAllWindows, !ruleEngine.hasRule(forBundleIdentifier: bundleIdentifier) {
            return nil
        }
        return HoverTarget(hit: hit, bundleIdentifier: bundleIdentifier, appName: app.localizedName)
    }

    /// Returns the traffic buttons of the window under the cursor, re-reading
    /// them via AX only when the CG window bounds changed (or the cache is
    /// empty); otherwise serves the cached values.
    private func resolveButtons(
        windowHit: AXQuery.WindowHit
    ) -> (buttons: [OverlayButtonInfo], axWindow: AXUIElement?) {
        let boundsUnchanged = !HoverOverlayGeometry.hasWindowBoundsChanged(
            previous: cachedWindowBounds,
            current: windowHit.bounds
        )
        if cachedWindowPID == windowHit.processIdentifier, boundsUnchanged {
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
        cachedWindowBounds = hit.bounds
    }

    func resetDetectionAndHide() {
        cachedButtons = []
        cachedAXWindow = nil
        cachedWindowPID = 0
        cachedWindowBounds = nil
        guard isOverlayVisible else { return }
        isOverlayVisible = false
        DispatchQueue.main.async { [weak self] in
            self?.hidePanels()
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

    private func hoveredPanelIndex(
        cursor: CGPoint,
        buttons: [OverlayButtonInfo],
        enlargedSize: CGFloat
    ) -> Int? {
        let frames = buttons.map(\.frame)
        let panelFrames = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: enlargedSize,
            containerBounds: Self.overlayContainerBounds(forButtonFrames: frames)
        )
        return panelFrames.firstIndex {
            HoverOverlayGeometry.isCursorInPanel(cursor: cursor, panelFrame: $0)
        }
    }
}
