import AppKit

/// Takes keyboard focus without activating Blinker or changing the focused application.
public final class WindowBrowserPanel: OverlayPanel {
    override public var canBecomeKey: Bool {
        true
    }

    override public var canBecomeMain: Bool {
        false
    }
}
