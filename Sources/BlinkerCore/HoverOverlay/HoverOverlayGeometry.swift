import CoreGraphics

/// Pure geometry helpers for the hover overlay, kept free of side effects so
/// they can be unit-tested in isolation. All frames are in AX (top-left
/// origin) global coordinates; the only AppKit conversion happens when panels
/// are created.
public enum HoverOverlayGeometry {
    /// Height of the band at the top of a window inside which the overlay
    /// reacts to the cursor.
    public static let titleBarBandHeight: CGFloat = 48

    /// Returns `true` when the cursor lies inside the window's top band.
    public static func isCursorInTitleBarBand(cursor: CGPoint, windowBounds: CGRect) -> Bool {
        windowBounds.contains(cursor) && cursor.y - windowBounds.minY <= titleBarBandHeight
    }

    /// The frame of the enlarged overlay panel centered on the original
    /// button frame.
    public static func panelFrame(forButtonFrame buttonFrame: CGRect, enlargedSize: CGFloat) -> CGRect {
        CGRect(
            x: buttonFrame.midX - enlargedSize / 2,
            y: buttonFrame.midY - enlargedSize / 2,
            width: enlargedSize,
            height: enlargedSize
        )
    }

    /// Returns `true` when the cursor lies within the enlarged panel frame.
    public static func isCursorInPanel(cursor: CGPoint, panelFrame: CGRect) -> Bool {
        panelFrame.contains(cursor)
    }

    /// Dwell progress (0...1) after `elapsedMilliseconds`; a dwell of `0` ms
    /// means immediate activation.
    public static func dwellProgress(elapsedMilliseconds: Double, dwellMilliseconds: Int) -> Double {
        guard dwellMilliseconds > 0 else { return 1 }
        return min(max(elapsedMilliseconds / Double(dwellMilliseconds), 0), 1)
    }

    /// Returns `true` when the CG window bounds changed enough to invalidate
    /// the cached button positions; sub-point jitter is ignored.
    public static func hasWindowBoundsChanged(previous: CGRect?, current: CGRect) -> Bool {
        guard let previous else { return true }
        return abs(previous.minX - current.minX) > 1
            || abs(previous.minY - current.minY) > 1
            || abs(previous.width - current.width) > 1
            || abs(previous.height - current.height) > 1
    }
}
