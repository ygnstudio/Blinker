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
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds

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
        .tileFirstThird: .firstThird,
        .tileCenterThird: .centerThird,
        .tileLastThird: .lastThird,
        .tileFirstTwoThirds: .firstTwoThirds,
        .tileLastTwoThirds: .lastTwoThirds,
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

    /// Preserve relative placement when transferring between unlike displays.
    public static func transferredFrame(_ frame: CGRect, from source: CGRect,
                                        to destination: CGRect) -> CGRect {
        let width = min(frame.width, destination.width)
        let height = min(frame.height, destination.height)
        let relativeX = (frame.minX - source.minX) / max(1, source.width - frame.width)
        let relativeY = (frame.minY - source.minY) / max(1, source.height - frame.height)
        return CGRect(x: destination.minX + min(max(relativeX, 0), 1) * (destination.width - width),
                      y: destination.minY + min(max(relativeY, 0), 1) * (destination.height - height),
                      width: width, height: height)
    }

    private static func thirdsFrame(_ placement: WindowPlacement, in visibleFrame: CGRect) -> CGRect {
        let start: CGFloat = placement == .centerThird || placement == .lastTwoThirds ? 1
            : placement == .lastThird ? 2 : 0
        let span: CGFloat = placement == .firstTwoThirds || placement == .lastTwoThirds ? 2 : 1
        // Portrait displays use horizontal bands, ordered from the top.
        if visibleFrame.height > visibleFrame.width {
            let unit = visibleFrame.height / 3
            return CGRect(x: visibleFrame.minX, y: visibleFrame.maxY - (start + span) * unit,
                          width: visibleFrame.width, height: unit * span)
        }
        let unit = visibleFrame.width / 3
        return CGRect(x: visibleFrame.minX + start * unit, y: visibleFrame.minY,
                      width: unit * span, height: visibleFrame.height)
    }

    /// One half or quadrant of `visibleFrame`, in AppKit's bottom-left-origin
    /// coordinates. The eight tile placements partition the screen exactly.
    /// Public so the settings UI can reuse the exact math for previews.
    public static func tiledFrame(_ placement: WindowPlacement, in visibleFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        switch placement {
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            return thirdsFrame(placement, in: visibleFrame)
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
