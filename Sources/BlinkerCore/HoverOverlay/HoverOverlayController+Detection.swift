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
/// window element to act on, the app identity and the enlarged panel frames.
struct OverlayLayout {
    let buttons: [OverlayButtonInfo]
    let axWindow: AXUIElement
    let target: HoverTarget
    let panelFrames: [CGRect]
}

// MARK: - Cursor tracking and AX detection (work queue only)

extension HoverOverlayController {
    func handleCursorMove(to location: CGPoint) {
        let settings = settingsStore.snapshot
        guard
            settings.isEnabled,
            let hit = AXQuery.windowUnderPoint(
                location,
                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            let app = NSRunningApplication(processIdentifier: hit.processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else {
            resetDetectionAndHide()
            return
        }
        if !settings.appliesToAllWindows, !ruleEngine.hasRule(forBundleIdentifier: bundleIdentifier) {
            resetDetectionAndHide()
            return
        }
        let target = HoverTarget(hit: hit, bundleIdentifier: bundleIdentifier, appName: app.localizedName)

        guard let layout = resolveWindowLayout(windowHit: hit, target: target, enlargedSize: settings.enlargedSize) else {
            resetDetectionAndHide()
            return
        }
        // Only wake up near the traffic lights themselves (or on top of an
        // already-enlarged panel) — not across the whole title bar band.
        guard HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: location,
            buttonFrames: layout.buttons.map(\.frame),
            panelFrames: layout.panelFrames
        ) else {
            resetDetectionAndHide()
            return
        }
        let hoveredIndex = layout.panelFrames.firstIndex {
            HoverOverlayGeometry.isCursorInPanel(cursor: location, panelFrame: $0)
        }
        syncPanels(layout: layout, hoveredIndex: hoveredIndex, settings: settings)
    }

    /// Resolves the traffic buttons for the window under the cursor and lays
    /// out the enlarged panels (clamped to the window ∩ screen container).
    /// Returns `nil` when the window exposes no traffic buttons.
    private func resolveWindowLayout(
        windowHit: AXQuery.WindowHit,
        target: HoverTarget,
        enlargedSize: CGFloat
    ) -> OverlayLayout? {
        let resolved = resolveButtons(windowHit: windowHit)
        guard !resolved.buttons.isEmpty, let axWindow = resolved.axWindow else { return nil }
        let frames = resolved.buttons.map(\.frame)
        let panelFrames = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: enlargedSize,
            containerBounds: Self.overlayContainerBounds(
                forButtonFrames: frames,
                windowBounds: windowHit.bounds
            )
        )
        return OverlayLayout(
            buttons: resolved.buttons,
            axWindow: axWindow,
            target: target,
            panelFrames: panelFrames
        )
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
}
