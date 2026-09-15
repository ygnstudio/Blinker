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
    /// The desktop (Space) the window was on when captured, as its stable
    /// UUID. Optional so pre-Space captures keep decoding; `nil` entries
    /// restore frame-only.
    public let spaceUUID: String?

    public init(
        bundleIdentifier: String,
        appName: String,
        frame: CGRect,
        spaceUUID: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.frame = frame
        self.spaceUUID = spaceUUID
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

    /// UserDefaults key shared with the App-layer toggle (the HUD restore
    /// path lives in Core and reads the same key). Default is off.
    static let spaceRestoreDefaultsKey = "workspaceSpaceRestoreEnabled"

    /// Serial queue keeping the AX-heavy capture/restore work off the main
    /// thread. The synchronous functions below run on it via the `Async`
    /// wrappers; serial ordering keeps rapid save/restore calls from
    /// interleaving AX writes.
    public static let axQueue = DispatchQueue(
        label: "com.ygnstudio.blinker.workspace-ax",
        qos: .userInitiated
    )

    // MARK: - Async entry points

    /// Captures the current arrangement on the AX queue; `completion`
    /// receives the entries on the main thread.
    public static func captureVisibleWindowsAsync(
        completion: @escaping ([WorkspaceEntry]) -> Void
    ) {
        axQueue.async {
            let entries = captureVisibleWindows()
            DispatchQueue.main.async { completion(entries) }
        }
    }

    /// Restores a workspace on the AX queue; `completion` receives the
    /// number of restored windows on the main thread.
    public static func restoreAsync(
        _ workspace: SavedWorkspace,
        completion: @escaping (Int) -> Void
    ) {
        axQueue.async {
            let restored = restore(workspace)
            DispatchQueue.main.async { completion(restored) }
        }
    }

    // MARK: - Capture

    /// A window that passed all capture filters, with the ids the Space
    /// bridge needs.
    private struct CaptureCandidate {
        let windowID: Int
        let bundleIdentifier: String
        let appName: String
        let frame: CGRect
    }

    /// Snapshots every regular-app window — on-screen, minimized and on
    /// other Spaces alike — one entry per window. Blinker's own windows are
    /// excluded. Uses the unfiltered window list because `.optionOnScreenOnly`
    /// silently drops everything outside the current Space, which made saved
    /// workspaces look empty (and restore a no-op) for most real layouts.
    /// Each entry also records the window's desktop (Space) UUID when the
    /// SkyLight bridge is available.
    public static func captureVisibleWindows() -> [WorkspaceEntry] {
        let candidates = captureCandidates()
        let spaceUUIDs = spaceUUIDsByWindowID(candidates.map(\.windowID))
        return candidates
            .map { candidate in
                WorkspaceEntry(
                    bundleIdentifier: candidate.bundleIdentifier,
                    appName: candidate.appName,
                    frame: candidate.frame,
                    spaceUUID: spaceUUIDs[candidate.windowID]
                )
            }
            .sorted {
                ($0.appName, $0.frame.minX, $0.frame.minY)
                    < ($1.appName, $1.frame.minX, $1.frame.minY)
            }
    }

    /// Filters the raw window list down to capture-worthy windows.
    private static func captureCandidates() -> [CaptureCandidate] {
        // The raw list reports every window the system knows about; the
        // frame is the last-known frame for hidden windows, which is
        // exactly what restore wants.
        let list = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var candidates: [CaptureCandidate] = []
        var seenFrames: Set<String> = []
        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let windowID = info[kCGWindowNumber as String] as? Int
            else { continue }
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

            candidates.append(CaptureCandidate(
                windowID: windowID,
                bundleIdentifier: bundleIdentifier,
                appName: app.localizedName ?? bundleIdentifier,
                frame: frame
            ))
        }
        return candidates
    }

    /// Maps window ids to Space UUIDs via the SkyLight bridge; empty when
    /// the bridge is unavailable, so captures simply store no Space.
    private static func spaceUUIDsByWindowID(_ windowIDs: [Int]) -> [Int: String] {
        guard SkyLightSpaces.isAvailable, !windowIDs.isEmpty else { return [:] }
        let catalog = Dictionary(
            uniqueKeysWithValues: SkyLightSpaces.spaceCatalog().map { ($0.id, $0.uuid) }
        )
        guard !catalog.isEmpty else { return [:] }
        return SkyLightSpaces.spacesForWindows(windowIDs).compactMapValues { catalog[$0] }
    }

    // MARK: - Restore

    /// Repositions saved windows onto running instances of the same apps.
    /// Entries are paired with the app's AX windows by size similarity (the
    /// closest current window wins), so multi-window apps restore every
    /// window instead of just the first. When the Space-restore preference
    /// is on (and the SkyLight bridge is available), restored windows are
    /// also moved back to the desktop they were captured on. Returns how
    /// many entries were restored; apps that are not running (or expose no
    /// AX window) are skipped silently — callers may log the miss.
    @discardableResult
    public static func restore(_ workspace: SavedWorkspace) -> Int {
        let restoreSpaces = UserDefaults.standard.bool(forKey: spaceRestoreDefaultsKey)
            && SkyLightSpaces.isAvailable
        var spaceIDByUUID: [String: Int64] = [:]
        var windowIDByFrame: [String: Int] = [:]
        if restoreSpaces {
            spaceIDByUUID = Dictionary(
                uniqueKeysWithValues: SkyLightSpaces.spaceCatalog().map { ($0.uuid, $0.id) }
            )
            windowIDByFrame = cgWindowSnapshot()
        }

        var restored = 0
        var pendingMoves: [(windowID: Int, spaceID: Int64)] = []
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
                // Resolve the Space move *before* writing the frame back:
                // the AX window still carries its current frame, which is
                // what the pre-restore snapshot indexed on.
                if let uuid = entry.spaceUUID,
                   let spaceID = spaceIDByUUID[uuid],
                   let currentFrame = elementFrame(windows[index]),
                   let windowID = windowIDByFrame[windowIDByFrameKey(
                       pid: app.processIdentifier,
                       frame: currentFrame
                   )] {
                    pendingMoves.append((windowID, spaceID))
                }
                AXQuery.setWindowFrame(axFrame: entry.frame, of: windows[index])
                restored += 1
            }
        }
        moveWindowsToSpaces(pendingMoves)
        return restored
    }

    /// One shot of (pid, frame → windowID) for layer-0 windows, taken
    /// before any frame is written back so each AX window's *current*
    /// frame matches the snapshot. The raw list is used on purpose —
    /// `.optionOnScreenOnly` drops other-Space windows.
    private static func cgWindowSnapshot() -> [String: Int] {
        let list = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] ?? []
        var snapshot: [String: Int] = [:]
        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let windowID = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            guard
                let boundsDictionary = info[kCGWindowBounds as String],
                // swiftlint:disable:next force_cast
                let frame = CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary)
            else { continue }
            snapshot[windowIDByFrameKey(pid: pid, frame: frame)] = windowID
        }
        return snapshot
    }

    /// Snapshot key: same pid and integral frame identifies one window.
    private static func windowIDByFrameKey(pid: pid_t, frame: CGRect) -> String {
        "\(pid)|\(frame.integral)"
    }

    /// Batch-moves the collected (window, Space) pairs, grouped per Space.
    private static func moveWindowsToSpaces(_ moves: [(windowID: Int, spaceID: Int64)]) {
        guard !moves.isEmpty else { return }
        let grouped = Dictionary(grouping: moves, by: \.spaceID)
        for (spaceID, group) in grouped {
            _ = SkyLightSpaces.moveWindows(group.map(\.windowID), toSpace: spaceID)
        }
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
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) ==
                .success,
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
