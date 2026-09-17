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
    ///
    /// Callers pass `panelFrames`/`trayFrame` only while the overlay is
    /// already visible: they extend the keep-alive zone, never the wake-up
    /// zone. Passing them before activation would balloon the trigger area
    /// to the whole enlarged group plus tray margins.
    ///
    /// `trayFrame` extends the alive zone to the glass tray's margins: the
    /// tray visually wraps the whole chip group, so gliding across its
    /// padding (the gaps between chips, the pill's rounded ends) must not
    /// tear the overlay down mid-move. The tray is not a hover surface —
    /// only actual chip frames count for `isCursorInPanel`.
    public static func isCursorInTriggerZone(
        cursor: CGPoint,
        buttonFrames: [CGRect],
        panelFrames: [CGRect],
        padding: CGFloat = triggerPadding,
        trayFrame: CGRect? = nil
    ) -> Bool {
        if let group = unionedBounds(of: buttonFrames) {
            let triggerBounds = group.insetBy(dx: -padding, dy: -padding)
            if triggerBounds.contains(cursor) {
                return true
            }
        }
        if let trayFrame, trayFrame.contains(cursor) {
            return true
        }
        return panelFrames.contains { isCursorInPanel(cursor: cursor, panelFrame: $0) }
    }

    /// How far (pt) the enlarged group's leading edge sits left of the
    /// native buttons' leading edge. The glass tray smears the leftmost
    /// native button into a soft ghost; anchoring slightly past it keeps
    /// that ghost fully covered by the first enlarged dot.
    public static let leadingAnchorInset: CGFloat = 6

    /// Computes non-overlapping panel frames for a group of traffic buttons.
    ///
    /// Real traffic lights sit only ~12–16 pt apart, far tighter than any
    /// enlarged diameter, so per-button centering makes enlarged panels
    /// overlap heavily. Instead the enlarged buttons are laid out left to
    /// right in their original order, anchored at the native group's leading
    /// edge (offset by `leadingAnchorInset`) and growing to the right, with a
    /// minimum gap between neighbors. Leading-edge anchoring — rather than
    /// group-center alignment — keeps the leftmost enlarged dot covering the
    /// native red button's glass-blurred ghost, and never pushes the group
    /// past the window's left edge.
    ///
    /// `extraCount` appends that many same-sized chips after the last traffic
    /// button (the user-configured extra buttons); the native chips keep
    /// their leading anchor and the group simply grows to the right.
    ///
    /// When `containerBounds` is given (the screen in AX coordinates), the
    /// whole group is shifted to stay inside it so edge-anchored windows
    /// (fullscreen, tiled) don't clip the enlarged buttons.
    public static func panelFrames(
        forButtonFrames buttonFrames: [CGRect],
        enlargedSize: CGFloat,
        minimumGap: CGFloat = 4,
        containerBounds: CGRect? = nil,
        extraCount: Int = 0
    ) -> [CGRect] {
        guard let first = buttonFrames.first else { return [] }
        let groupBounds = unionedBounds(of: buttonFrames) ?? first
        let nativeCount = CGFloat(buttonFrames.count)
        let totalCount = nativeCount + CGFloat(extraCount)
        // The native chips stay anchored to the native group's leading edge;
        // extra chips continue after them, so enabling extras never
        // displaces the traffic lights themselves.
        var originX = groupBounds.minX - leadingAnchorInset
        let originY = groupBounds.midY - enlargedSize / 2
        var frames: [CGRect] = []
        frames.reserveCapacity(Int(totalCount))
        for _ in 0 ..< Int(totalCount) {
            frames.append(CGRect(x: originX, y: originY, width: enlargedSize, height: enlargedSize))
            originX += enlargedSize + minimumGap
        }
        guard let container = containerBounds else { return frames }
        // Shift the whole assembly (natives included) to stay inside; the
        // two passes mirror `clampedOrigin` for the leading and trailing
        // edges respectively.
        if let lastMaxX = frames.last?.maxX, lastMaxX > container.maxX {
            let delta = container.maxX - lastMaxX
            frames = frames.map { $0.offsetBy(dx: delta, dy: 0) }
        }
        if let firstMinX = frames.first?.minX, firstMinX < container.minX {
            let delta = container.minX - firstMinX
            frames = frames.map { $0.offsetBy(dx: delta, dy: 0) }
        }
        let clampedY = clampedOrigin(
            originY,
            length: enlargedSize,
            lowerBound: container.minY,
            upperBound: container.maxY
        )
        if clampedY != originY {
            let delta = clampedY - originY
            frames = frames.map { $0.offsetBy(dx: 0, dy: delta) }
        }
        return frames
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

    /// Amazon-style "safe triangle", generalized to a corridor: the region
    /// between the chip that opened a popup panel and the panel itself. The
    /// straight path from the chip to the panel crosses open space where the
    /// normal detection would read a hover-out and tear everything down
    /// mid-move; while the cursor travels through this corridor the popup
    /// must stay open. The corridor is the quadrilateral from the anchor's
    /// bottom edge to the panel's top edge (both in AX top-left coordinates,
    /// so "bottom" is `maxY` and "top" is `minY`); it stays convex even when
    /// the panel was clamped horizontally away from the chip.
    public static func safeCorridorContains(cursor: CGPoint, anchor: CGRect, panel: CGRect) -> Bool {
        let corners = [
            CGPoint(x: anchor.minX, y: anchor.maxY),
            CGPoint(x: anchor.maxX, y: anchor.maxY),
            CGPoint(x: panel.maxX, y: panel.minY),
            CGPoint(x: panel.minX, y: panel.minY),
        ]
        return Self.polygonContains(cursor, corners)
    }

    /// Even-odd ray-casting point-in-polygon test.
    private static func polygonContains(_ point: CGPoint, _ vertices: [CGPoint]) -> Bool {
        var inside = false
        var previous = vertices.count - 1
        for index in 0 ..< vertices.count {
            let current = vertices[index]
            let earlier = vertices[previous]
            let crossesHorizontally =
                (current.y > point.y) != (earlier.y > point.y)
            let crossingX = (earlier.x - current.x) * (point.y - current.y)
                / (earlier.y - current.y) + current.x
            if crossesHorizontally, point.x < crossingX {
                inside.toggle()
            }
            previous = index
        }
        return inside
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
