import Foundation

/// Main-thread screen snapshots become plain Quartz rectangles for the tap.
/// A generous edge band includes Dock magnification and its auto-hide entrance.
enum DockClickScreenRegions {
    static func make(screens: [CGRect], coordinatePivotY: CGFloat, depth: CGFloat = 200) -> [CGRect] {
        guard coordinatePivotY.isFinite, depth.isFinite, depth > 0 else { return [] }
        return screens.flatMap { screen -> [CGRect] in
            guard !screen.isNull, !screen.isInfinite, screen.width > 0, screen.height > 0 else { return [] }
            let quartz = CGRect(x: screen.minX, y: coordinatePivotY - screen.maxY,
                                width: screen.width, height: screen.height)
            let horizontal = min(depth, quartz.width)
            let vertical = min(depth, quartz.height)
            return [
                CGRect(x: quartz.minX, y: quartz.minY, width: horizontal, height: quartz.height),
                CGRect(x: quartz.maxX - horizontal, y: quartz.minY, width: horizontal, height: quartz.height),
                CGRect(x: quartz.minX, y: quartz.maxY - vertical, width: quartz.width, height: vertical),
            ]
        }
    }
}
