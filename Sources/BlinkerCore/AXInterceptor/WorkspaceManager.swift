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

    /// Snapshots every visible regular-app window, one entry per app (the
    /// largest window wins). Blinker's own windows are excluded.
    public static func captureVisibleWindows() -> [WorkspaceEntry] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var best: [String: WorkspaceEntry] = [:]
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

            let entry = WorkspaceEntry(
                bundleIdentifier: bundleIdentifier,
                appName: app.localizedName ?? bundleIdentifier,
                frame: frame
            )
            if let existing = best[bundleIdentifier], area(existing) >= area(entry) {
                continue
            }
            best[bundleIdentifier] = entry
        }
        return Array(best.values)
    }

    private static func area(_ entry: WorkspaceEntry) -> CGFloat {
        entry.frame.width * entry.frame.height
    }

    // MARK: - Restore

    /// Repositions one window per saved entry onto a running instance of the
    /// same app. Returns how many entries were restored; apps that are not
    /// running (or expose no AX window) are skipped silently — callers may
    /// log the miss.
    @discardableResult
    public static func restore(_ workspace: SavedWorkspace) -> Int {
        var restored = 0
        let running = NSWorkspace.shared.runningApplications
        for entry in workspace.entries {
            guard let app = running.first(where: {
                $0.bundleIdentifier == entry.bundleIdentifier
            }) else { continue }
            guard let window = firstWindowElement(processIdentifier: app.processIdentifier) else {
                continue
            }
            AXQuery.setWindowFrame(axFrame: entry.frame, of: window)
            restored += 1
        }
        return restored
    }

    /// The app's first AX window — the one most likely to be the user's main
    /// surface. Minimized windows are rarely first, and moving hidden windows
    /// would only surprise.
    private static func firstWindowElement(processIdentifier: pid_t) -> AXUIElement? {
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
            let window = windows.first
        else { return nil }
        return window
    }
}
