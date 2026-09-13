import CoreGraphics

/// Pure geometry helpers for the hover overlay, kept free of side effects so
/// they can be unit-tested in isolation. All frames are in AX (top-left
/// origin) global coordinates; the only AppKit conversion happens when panels
/// are created.
public enum HoverOverlayGeometry {
    /// How far (pt) beyond the native buttons' bounding box the cursor may
    /// travel before the overlay hides. Tight on purpose: the overlay should
    /// only wake up near the traffic lights, not across the whole title bar.
    public static let triggerPadding: CGFloat = 12

    /// Returns `true` when the cursor is close enough to the native buttons
    /// — or already over one of the enlarged panels — to keep the overlay
    /// alive. Including the panels prevents a hide/flicker loop when the
    /// cursor moves from a native button onto its enlarged neighbor.
    public static func isCursorInTriggerZone(
        cursor: CGPoint,
        buttonFrames: [CGRect],
        panelFrames: [CGRect],
        padding: CGFloat = triggerPadding
    ) -> Bool {
        if let group = unionedBounds(of: buttonFrames),
           group.insetBy(dx: -padding, dy: -padding).contains(cursor) {
            return true
        }
        return panelFrames.contains { isCursorInPanel(cursor: cursor, panelFrame: $0) }
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

    /// Computes non-overlapping panel frames for a group of traffic buttons.
    ///
    /// Real traffic lights sit only ~12–16 pt apart, far tighter than any
    /// enlarged diameter, so per-button centering makes enlarged panels
    /// overlap heavily. Instead the enlarged buttons are laid out left to
    /// right in their original order, centered as a group on the original
    /// buttons' bounding box, with a minimum gap between neighbors.
    ///
    /// When `containerBounds` is given (the screen in AX coordinates), the
    /// whole group is shifted to stay inside it so edge-anchored windows
    /// (fullscreen, tiled) don't clip the enlarged buttons.
    public static func panelFrames(
        forButtonFrames buttonFrames: [CGRect],
        enlargedSize: CGFloat,
        minimumGap: CGFloat = 4,
        containerBounds: CGRect? = nil
    ) -> [CGRect] {
        guard let first = buttonFrames.first else { return [] }
        let groupBounds = unionedBounds(of: buttonFrames) ?? first
        let count = CGFloat(buttonFrames.count)
        let totalWidth = count * enlargedSize + (count - 1) * minimumGap
        var originX = groupBounds.midX - totalWidth / 2
        var originY = groupBounds.midY - enlargedSize / 2
        if let container = containerBounds {
            originX = clampedOrigin(
                originX,
                length: totalWidth,
                lowerBound: container.minX,
                upperBound: container.maxX
            )
            originY = clampedOrigin(
                originY,
                length: enlargedSize,
                lowerBound: container.minY,
                upperBound: container.maxY
            )
        }
        return buttonFrames.map { _ in
            let frame = CGRect(
                x: originX,
                y: originY,
                width: enlargedSize,
                height: enlargedSize
            )
            originX += enlargedSize + minimumGap
            return frame
        }
    }

    /// The bounding box union of the given frames, or `nil` when empty.
    public static func unionedBounds(of frames: [CGRect]) -> CGRect? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Clamps a layout origin of the given length into `[lower, upper]`,
    /// preferring the leading edge when the length exceeds the container.
    private static func clampedOrigin(
        _ origin: CGFloat,
        length: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        let maxOrigin = upperBound - length
        guard maxOrigin >= lowerBound else { return lowerBound }
        return min(max(origin, lowerBound), maxOrigin)
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
