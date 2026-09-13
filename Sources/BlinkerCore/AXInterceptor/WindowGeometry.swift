import CoreGraphics

/// Window placement options shared by the geometry actions.
public enum WindowPlacement: String, Sendable, CaseIterable {
    case maximize
    case almostMaximize
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center

    /// The placement corresponding to `action`, or `nil` when the action is
    /// not a frame placement (e.g. `.moveToNextDisplay`, which the performer
    /// handles separately).
    init?(action: ButtonAction) {
        guard let placement = Self.actionMapping[action] else { return nil }
        self = placement
    }

    private static let actionMapping: [ButtonAction: WindowPlacement] = [
        .maximize: .maximize,
        .almostMaximize: .almostMaximize,
        .tileLeft: .left,
        .tileRight: .right,
        .tileTop: .top,
        .tileBottom: .bottom,
        .tileTopLeft: .topLeft,
        .tileTopRight: .topRight,
        .tileBottomLeft: .bottomLeft,
        .tileBottomRight: .bottomRight,
        .centerWindow: .center,
    ]
}

/// Pure window-placement math: maps a placement to a target frame inside a
/// screen's visible frame. Free of AX and AppKit dependencies so it can be
/// unit-tested without a display server.
public enum WindowGeometry {
    /// Fraction of the screen kept free around an almost-maximized window.
    static let almostMaximizeMargin: CGFloat = 0.075

    /// The target AppKit frame for `placement`.
    ///
    /// `originalFrame` is only used by `.center`, which keeps the window's
    /// size; every other placement fully determines the result.
    public static func targetFrame(
        for placement: WindowPlacement,
        originalFrame: CGRect,
        in visibleFrame: CGRect
    ) -> CGRect {
        switch placement {
        case .maximize:
            visibleFrame
        case .almostMaximize:
            almostMaximizedFrame(in: visibleFrame)
        case .center:
            centeredFrame(originalFrame: originalFrame, in: visibleFrame)
        default:
            tiledFrame(placement, in: visibleFrame)
        }
    }

    /// A near-full-screen frame with symmetric breathing margins.
    static func almostMaximizedFrame(in visibleFrame: CGRect) -> CGRect {
        let width = visibleFrame.width * (1 - almostMaximizeMargin * 2)
        let height = visibleFrame.height * (1 - almostMaximizeMargin * 2)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Keeps the window's size, moving only its center to the screen's center.
    static func centeredFrame(originalFrame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - originalFrame.width / 2,
            y: visibleFrame.midY - originalFrame.height / 2,
            width: originalFrame.width,
            height: originalFrame.height
        )
    }

    /// One half or quadrant of `visibleFrame`, in AppKit's bottom-left-origin
    /// coordinates. The eight tile placements partition the screen exactly.
    /// Public so the settings UI can reuse the exact math for previews.
    public static func tiledFrame(_ placement: WindowPlacement, in visibleFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        switch placement {
        case .left:
            return CGRect(
                x: visibleFrame.minX, y: visibleFrame.minY,
                width: halfWidth, height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.midX, y: visibleFrame.minY,
                width: halfWidth, height: visibleFrame.height
            )
        case .top:
            return CGRect(
                x: visibleFrame.minX, y: visibleFrame.midY,
                width: visibleFrame.width, height: halfHeight
            )
        case .bottom:
            return CGRect(
                x: visibleFrame.minX, y: visibleFrame.minY,
                width: visibleFrame.width, height: halfHeight
            )
        case .topLeft:
            return CGRect(
                x: visibleFrame.minX, y: visibleFrame.midY,
                width: halfWidth, height: halfHeight
            )
        case .topRight:
            return CGRect(
                x: visibleFrame.midX, y: visibleFrame.midY,
                width: halfWidth, height: halfHeight
            )
        case .bottomLeft:
            return CGRect(
                x: visibleFrame.minX, y: visibleFrame.minY,
                width: halfWidth, height: halfHeight
            )
        case .bottomRight:
            return CGRect(
                x: visibleFrame.midX, y: visibleFrame.minY,
                width: halfWidth, height: halfHeight
            )
        default:
            return visibleFrame
        }
    }
}
