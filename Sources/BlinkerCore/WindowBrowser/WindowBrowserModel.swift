import CoreGraphics
import Foundation

/// Stable AX identity is kept separately from the optional screenshot identity.
/// A missing or ambiguous CG match must never change which window an action targets.
public struct BrowserWindow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let pid: Int32
    public let appName: String
    public let title: String
    public let bundleID: String
    public let frame: CGRect
    public let captureID: UInt32?
    public let isMinimized: Bool
    public let isHidden: Bool
    public let isOnScreen: Bool
    public let focusOrder: UInt64
    public var isTab = false
    public var isSelectedTab = true
    /// The parent AX window's raw title, independent of tab labels or the app-name display fallback.
    var captureTitle: String?
}

public struct WindowBrowserSelection: Sendable {
    public private(set) var ids: [UUID] = []
    public private(set) var selected: UUID?

    public init() {}

    public mutating func replace(_ newIDs: [UUID], preferred: UUID? = nil) {
        let oldIndex = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
        ids = newIDs
        if let preferred, ids.contains(preferred) {
            selected = preferred
        } else if let selected, ids.contains(selected) {
            return
        } else {
            selected = ids.isEmpty ? nil : ids[min(oldIndex, ids.count - 1)]
        }
    }

    public mutating func move(_ delta: Int) {
        guard !ids.isEmpty else { selected = nil; return }
        let index = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
        selected = ids[((index + delta) % ids.count + ids.count) % ids.count]
    }
}

public struct WindowBrowserLayout {
    public let size: CGSize
    public let thumbnailHeight: CGFloat
    public let columns: Int
    public let rows: Int
}

public enum WindowBrowserGeometry {
    /// Scale the entire surface, including its chrome, from one logical layout. Both
    /// content and panel use this result so screen clamping cannot clip the grid.
    public static func previewLayout(windowCount: Int, scale: Double,
                                     screenSize: CGSize) -> WindowBrowserLayout {
        let factor = scale.isFinite ? min(1.5, max(0.5, scale)) : 1
        let count = max(1, windowCount)
        let available = CGSize(width: max(0, (screenSize.width - 20) / factor),
                               height: max(0, (screenSize.height - 20) / factor))
        let desiredColumns = count <= 6 ? min(3, count) : Int(ceil(sqrt(Double(count) * 1.5)))
        let columns = min(desiredColumns, max(1, Int((available.width - 32) / 110)))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let thumbnailHeight = max(44, min(110, (available.height - 80) / CGFloat(rows) - 64))
        let width = min(available.width, CGFloat(columns) * 224 + 32)
        return WindowBrowserLayout(
            size: CGSize(
                width: width * factor,
                height: min(available.height, CGFloat(rows) * (thumbnailHeight + 64) + 80) * factor
            ),
            thumbnailHeight: thumbnailHeight, columns: columns, rows: rows
        )
    }

    /// AppKit global coordinates. Dock can sit on any edge of an offset display.
    public static func panelFrame(size: CGSize, anchor: CGRect?, screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: 10, dy: 10)
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        var origin = CGPoint(x: area.midX - width / 2, y: area.midY - height / 2)
        if let anchor {
            let left = abs(anchor.midX - screen.minX)
            let right = abs(anchor.midX - screen.maxX)
            let bottom = abs(anchor.midY - screen.minY)
            if bottom <= min(left, right) {
                origin = CGPoint(x: anchor.midX - width / 2, y: anchor.maxY + 10)
            } else if left < right {
                origin = CGPoint(x: anchor.maxX + 10, y: anchor.midY - height / 2)
            } else {
                origin = CGPoint(x: anchor.minX - width - 10, y: anchor.midY - height / 2)
            }
        }
        return CGRect(x: min(max(origin.x, area.minX), area.maxX - width),
                      y: min(max(origin.y, area.minY), area.maxY - height), width: width, height: height)
    }
}

public enum WindowBrowserRequest {
    public static let showApplication = Notification.Name("BlinkerShowApplicationWindows")
}
