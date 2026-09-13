import CoreGraphics

/// Pure hit-testing for drag-to-snap zones: given the cursor and a screen's
/// visible frame, returns the window placement the cursor is asking for.
///
/// Zones mirror Rectangle's defaults — screen edges tile to halves, the top
/// edge maximizes, and the four corners tile to quadrants. Free of AppKit so
/// it can be unit-tested without a display server.
public enum SnapZones {
    /// Distance from an edge (in points) inside which the cursor counts as
    /// "on" that edge.
    public static let edgeInset: CGFloat = 6
    /// Width of the corner zones measured inward along the top/bottom edges.
    public static let cornerExtent: CGFloat = 80

    /// The placement requested by `point`, or `nil` when the cursor is not
    /// inside any snap zone.
    public static func placement(at point: CGPoint, in visibleFrame: CGRect) -> WindowPlacement? {
        let nearLeft = point.x <= visibleFrame.minX + edgeInset
        let nearRight = point.x >= visibleFrame.maxX - edgeInset
        let nearTop = point.y >= visibleFrame.maxY - edgeInset
        let nearBottom = point.y <= visibleFrame.minY + edgeInset

        // Corners first — along the top/bottom edges, points within
        // `cornerExtent` of a side edge belong to that corner quadrant.
        if nearTop {
            if point.x <= visibleFrame.minX + cornerExtent {
                return .topLeft
            }
            if point.x >= visibleFrame.maxX - cornerExtent {
                return .topRight
            }
            return .maximize
        }
        if nearBottom {
            if point.x <= visibleFrame.minX + cornerExtent {
                return .bottomLeft
            }
            if point.x >= visibleFrame.maxX - cornerExtent {
                return .bottomRight
            }
            return .bottom
        }
        if nearLeft {
            return .left
        }
        if nearRight {
            return .right
        }
        return nil
    }
}
