import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// One captured window inside a workspace: which app and where its window
/// was. The frame is in AX (top-left origin) global coordinates — the same
/// coordinate space `CGWindowList` reports and AX writes back, so capture
/// and restore need no conversion.
public struct WorkspaceEntry: Codable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let appName: String
    public let frame: CGRect

    public init(bundleIdentifier: String, appName: String, frame: CGRect) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.frame = frame
    }
}

/// A named snapshot of a whole window arrangement ("写代码", "开会", …).
public struct SavedWorkspace: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var entries: [WorkspaceEntry]

    public init(id: UUID = UUID(), name: String, entries: [WorkspaceEntry]) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}

/// Captures and restores window layouts. `WorkspaceStore` owns persistence;
/// the static helpers here do the screen-facing work so they can stay free
/// of observable state.
public enum WorkspaceManager {
    /// Minimum window size worth capturing; hides tooltips and helper
    /// panels that would turn restoring into a mess.
    static let minimumCaptureSize = CGSize(width: 120, height: 80)

    // MARK: - Capture

    /// Snapshots every regular-app window — on-screen, minimized and on
    /// other Spaces alike — one entry per window. Blinker's own windows are
    /// excluded. Uses the unfiltered window list because `.optionOnScreenOnly`
    /// silently drops everything outside the current Space, which made saved
    /// workspaces look empty (and restore a no-op) for most real layouts.
    public static func captureVisibleWindows() -> [WorkspaceEntry] {
        // The raw list reports every window the system knows about; pair it
        // with the on-screen list so entries can note nothing extra — the
        // frame is the last-known frame for hidden windows, which is exactly
        // what restore wants.
        let list = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var entries: [WorkspaceEntry] = []
        var seenFrames: Set<String> = []
        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0 else { continue }
            guard
                let boundsDictionary = info[kCGWindowBounds as String],
                // swiftlint:disable:next force_cast
                let frame = CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary),
                frame.width >= minimumCaptureSize.width,
                frame.height >= minimumCaptureSize.height
            else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else {
                continue
            }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular,
                  let bundleIdentifier = app.bundleIdentifier
            else { continue }
            // The raw list contains window proxies (e.g. full-width title-bar
            // strips) that share a frame; one entry per distinct frame.
            let frameKey = "\(bundleIdentifier)|\(frame.integral)"
            guard seenFrames.insert(frameKey).inserted else { continue }

            entries.append(WorkspaceEntry(
                bundleIdentifier: bundleIdentifier,
                appName: app.localizedName ?? bundleIdentifier,
                frame: frame
            ))
        }
        return entries.sorted {
            ($0.appName, $0.frame.minX, $0.frame.minY)
                < ($1.appName, $1.frame.minX, $1.frame.minY)
        }
    }

    // MARK: - Restore

    /// Repositions saved windows onto running instances of the same apps.
    /// Entries are paired with the app's AX windows by size similarity (the
    /// closest current window wins), so multi-window apps restore every
    /// window instead of just the first. Returns how many entries were
    /// restored; apps that are not running (or expose no AX window) are
    /// skipped silently — callers may log the miss.
    @discardableResult
    public static func restore(_ workspace: SavedWorkspace) -> Int {
        var restored = 0
        let running = NSWorkspace.shared.runningApplications
        let entriesByApp = Dictionary(grouping: workspace.entries, by: \.bundleIdentifier)
        for (bundleIdentifier, entries) in entriesByApp {
            guard let app = running.first(where: {
                $0.bundleIdentifier == bundleIdentifier
            }) else { continue }
            guard let windows = axWindows(processIdentifier: app.processIdentifier), !windows.isEmpty
            else { continue }

            var used: Set<Int> = []
            for entry in entries {
                guard let index = bestWindowIndex(for: entry.frame, in: windows, used: used) else {
                    continue
                }
                used.insert(index)
                AXQuery.setWindowFrame(axFrame: entry.frame, of: windows[index])
                restored += 1
            }
        }
        return restored
    }

    /// Picks the unused AX window whose current area is closest to the saved
    /// frame's area — a cheap size fingerprint that survives position changes
    /// and pairs multi-window apps sensibly.
    private static func bestWindowIndex(
        for frame: CGRect,
        in windows: [AXUIElement],
        used: Set<Int>
    ) -> Int? {
        let savedArea = frame.width * frame.height
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, window) in windows.enumerated() where !used.contains(index) {
            guard let current = elementFrame(window) else { continue }
            let area = current.width * current.height
            let distance = abs(area - savedArea)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) ==
            .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let positionValue = positionRef, let sizeValue = sizeRef
        else { return nil }
        var point = CGPoint()
        var size = CGSize()
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) // swiftlint:disable:this force_cast
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
        return CGRect(origin: point, size: size)
    }

    /// All of the app's AX windows, any state — minimized windows keep their
    /// last frame, so repositioning them lands correctly when un-minimized.
    private static func axWindows(processIdentifier: pid_t) -> [AXUIElement]? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        AXQuery.applyMessagingTimeout(appElement)
        var windowsRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            ) == .success,
            let windows = windowsRef as? [AXUIElement],
            !windows.isEmpty
        else { return nil }
        return windows
    }
}
