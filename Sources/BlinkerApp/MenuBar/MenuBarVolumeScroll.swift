import AppKit

/// A local event monitor scoped to this panel, never to the desktop or other apps.
@MainActor
final class MenuBarVolumeScroll {
    private var token: Any?
    private var accumulated: CGFloat = 0
    private var previousTime: TimeInterval = 0
    private var targetVolume: Double?
    private var targetDevice: UInt32?

    func start(window: NSWindow, audio: SystemAudioController, preferences: MenuBarPreferences) {
        stop()
        let handler: (NSEvent) -> NSEvent? = { [weak self, weak window, weak audio] event in
            guard let self, let window, let audio else { return event }
            return handle(event, window: window, audio: audio, preferences: preferences)
        }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: handler)
    }

    private func handle(_ event: NSEvent, window: NSWindow, audio: SystemAudioController,
                        preferences: MenuBarPreferences) -> NSEvent? {
        guard event.window === window, window.isVisible,
              preferences.configuration.scrollAdjustsVolume,
              preferences.configuration.enabledSections.contains(.volume),
              audio.canSetVolume, let current = audio.volume,
              event.momentumPhase.isEmpty, event.scrollingDeltaY.isFinite else { return event }
        let config = preferences.configuration
        if config.scrollScope == .volumeControl,
           !Self.isOverVolumeControl(event.locationInWindow, in: window) {
            return event
        }
        // Scrolling device lists remains scrolling, including under the panel-wide option.
        if Self.isOverDeviceList(event.locationInWindow, in: window) {
            return event
        }
        if event.timestamp - previousTime > 0.3 || targetDevice != audio.currentDeviceID {
            accumulated = 0
            targetVolume = current
            targetDevice = audio.currentDeviceID
        }
        previousTime = event.timestamp
        var delta = event.scrollingDeltaY
        if !config.naturalScrolling, event.isDirectionInvertedFromDevice {
            delta = -delta
        }
        if config.scrollDirection == .down {
            delta = -delta
        }
        accumulated += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
        let steps = Int(min(20, max(-20, accumulated / threshold)))
        guard steps != 0 else { return nil }
        accumulated -= CGFloat(steps) * threshold
        let target = min(1, max(0, (targetVolume ?? current) + Double(steps) * 0.02))
        targetVolume = target
        audio.setVolume(target)
        return nil
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        accumulated = 0
        targetVolume = nil
        targetDevice = nil
    }

    private static func isOverVolumeControl(_ point: NSPoint, in window: NSWindow) -> Bool {
        contains(marker: "BlinkerVolumeControl", point: point, root: window.contentView)
    }

    private static func isOverDeviceList(_ point: NSPoint, in window: NSWindow) -> Bool {
        contains(marker: "BlinkerAudioDeviceList", point: point, root: window.contentView)
    }

    private static func contains(marker: String, point: NSPoint, root: NSView?) -> Bool {
        guard let root, !root.isHiddenOrHasHiddenAncestor else { return false }
        if root.identifier?.rawValue == marker,
           root.visibleRect.contains(root.convert(point, from: nil)) {
            return true
        }
        return root.subviews.contains { contains(marker: marker, point: point, root: $0) }
    }

    deinit {
        if let token {
            NSEvent.removeMonitor(token)
        }
    }
}
