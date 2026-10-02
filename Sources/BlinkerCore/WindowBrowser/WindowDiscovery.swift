import AppKit
import ApplicationServices

/// All AX IPC and identity bookkeeping live on the catalog's serial worker.
final class WindowDiscovery: @unchecked Sendable {
    struct Target {
        let id: UUID
        let pid: pid_t
        let element: AXUIElement
        var focusOrder: UInt64 = 0
        var tab: AXUIElement?
    }

    private(set) var targets: [UUID: Target] = [:]
    private var sequence: UInt64 = 0
    private var lastWindows: [BrowserWindow] = []

    func discover(apps: [NSRunningApplication], focusedPID: pid_t?,
                  includeTabs: Bool = false) -> [BrowserWindow] {
        guard AccessibilityPermission.isTrusted else { targets = [:]; return [] }
        let surfaces = AXQuery.copyWindowList([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        var result: [BrowserWindow] = []
        var retained: [UUID: Target] = [:]
        for app in apps where !app.isTerminated {
            let pid = app.processIdentifier
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.08)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else {
                result += cachedWindows(pid: pid, retained: &retained)
                continue
            }
            let focused = pid == focusedPID ? AXQuery.focusedWindowElement(processIdentifier: pid) : nil
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.08)
                guard let frame = AXQuery.elementFrame(window), frame.width > 40, frame.height > 30,
                      AXQuery.stringAttribute(window, kAXRoleAttribute) == kAXWindowRole else { continue }
                let subrole = AXQuery.stringAttribute(window, kAXSubroleAttribute)
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                let title = AXQuery.stringAttribute(window, kAXTitleAttribute) ?? ""
                var target = targets.values.first {
                    $0.pid == pid && $0.tab == nil && CFEqual($0.element, window)
                }
                    ?? Target(id: UUID(), pid: pid, element: window)
                if let focused, CFEqual(focused, window) {
                    sequence += 1
                    target.focusOrder = sequence
                }
                retained[target.id] = target
                let minimized = bool(window, kAXMinimizedAttribute)
                let match = Self.captureMatch(surfaces, pid: pid, frame: frame, title: title,
                                              allowOffscreenTitleMatch: minimized || app.isHidden)
                let browserWindow = BrowserWindow(
                    id: target.id, pid: pid, appName: app.localizedName ?? app.bundleIdentifier ?? "",
                    title: title.isEmpty ? (app.localizedName ?? "") : title,
                    bundleID: app.bundleIdentifier ?? "", frame: frame,
                    captureID: match?[kCGWindowNumber as String] as? UInt32,
                    isMinimized: minimized, isHidden: app.isHidden,
                    isOnScreen: match?[kCGWindowIsOnscreen as String] as? Bool ?? false,
                    focusOrder: target.focusOrder, captureTitle: title
                )
                result += expandedWindows(browserWindow, target: target,
                                          includeTabs: includeTabs, retained: &retained)
            }
        }
        targets = retained
        lastWindows = sorted(result, surfaces: surfaces)
        return lastWindows
    }

    private func cachedWindows(pid: pid_t, retained: inout [UUID: Target]) -> [BrowserWindow] {
        let cached = lastWindows.filter { $0.pid == pid }
        for window in cached {
            retained[window.id] = targets[window.id]
        }
        return cached
    }

    private func expandedWindows(_ window: BrowserWindow, target: Target, includeTabs: Bool,
                                 retained: inout [UUID: Target]) -> [BrowserWindow] {
        guard includeTabs else {
            return [window]
        }
        let expanded = tabWindows(window, target: target, retained: &retained)
        return expanded.isEmpty ? [window] : expanded
    }

    private func tabWindows(_ window: BrowserWindow, target: Target,
                            retained: inout [UUID: Target]) -> [BrowserWindow] {
        WindowTabDiscovery.tabs(in: target.element, bundleID: window.bundleID).map { tab in
            let old = targets.values.first {
                $0.pid == target.pid && $0.tab.map { CFEqual($0, tab.element) } == true
            }
            let id = old?.id ?? UUID()
            let order = tab.selected ? target.focusOrder : old?.focusOrder ?? 0
            retained[id] = Target(id: id, pid: target.pid, element: target.element,
                                  focusOrder: order, tab: tab.element)
            return BrowserWindow(id: id, pid: window.pid, appName: window.appName, title: tab.title,
                                 bundleID: window.bundleID, frame: window.frame,
                                 captureID: tab.selected ? window.captureID : nil,
                                 isMinimized: window.isMinimized, isHidden: window.isHidden,
                                 isOnScreen: tab.selected && window.isOnScreen, focusOrder: order,
                                 isTab: true, isSelectedTab: tab.selected, captureTitle: window.captureTitle)
        }
    }

    func canCapture(_ id: UUID) -> Bool {
        guard let target = targets[id] else { return false }
        return target.tab.map(WindowTabDiscovery.isSelected) ?? true
    }

    private func sorted(_ result: [BrowserWindow], surfaces: [[String: Any]]) -> [BrowserWindow] {
        let zOrder = surfaces.compactMap { $0[kCGWindowNumber as String] as? UInt32 }
        return result.sorted {
            if $0.focusOrder != $1.focusOrder {
                return $0.focusOrder > $1.focusOrder
            }
            let left = $0.captureID.flatMap { zOrder.firstIndex(of: $0) } ?? Int.max
            let right = $1.captureID.flatMap { zOrder.firstIndex(of: $0) } ?? Int.max
            if left != right {
                return left < right
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Conservative public-API matching. Ambiguous same-frame windows get an icon, not somebody else's image.
    static func captureMatch(_ surfaces: [[String: Any]], pid: pid_t, frame: CGRect,
                             title: String, allowOffscreenTitleMatch: Bool = false) -> [String: Any]? {
        let owned = surfaces.filter { info in
            info[kCGWindowOwnerPID as String] as? pid_t == pid
                && info[kCGWindowLayer as String] as? Int == 0
        }
        // A hidden/minimized window's old frame can now belong to another window.
        // Only a unique known title can identify a cold offscreen capture.
        if allowOffscreenTitleMatch {
            guard !title.isEmpty else { return nil }
            let titled = owned.filter { $0[kCGWindowName as String] as? String == title }
            return titled.count == 1 ? titled.first : nil
        }
        let matches = owned.filter { info in
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let candidate = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }
            return WindowLayoutHistory<UUID>.matches(candidate, frame)
        }
        guard !title.isEmpty else { return matches.count == 1 ? matches.first : nil }
        let titled = matches.filter { $0[kCGWindowName as String] as? String == title }
        if titled.count == 1 {
            return titled.first
        }
        // Missing source titles can fall back to a unique current frame. A known
        // contradicting title is evidence of another window, never a fallback.
        guard matches.count == 1, let candidate = matches.first,
              (candidate[kCGWindowName as String] as? String ?? "").isEmpty else { return nil }
        return candidate
    }

    func focus(_ id: UUID) -> Bool {
        guard let target = targets[id], let app = NSRunningApplication(processIdentifier: target.pid),
              !app.isTerminated,
              AXQuery.stringAttribute(target.element, kAXRoleAttribute) == kAXWindowRole else { return false }
        AXUIElementSetAttributeValue(target.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        app.unhide()
        app.activate(options: [])
        let result = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let tab = target.tab {
            guard AXUIElementPerformAction(tab, kAXPressAction as CFString) == .success else { return false }
            return true
        }
        return result == .success
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? Bool ?? false
    }
}
