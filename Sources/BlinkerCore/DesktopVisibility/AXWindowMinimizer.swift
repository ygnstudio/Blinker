import AppKit
import ApplicationServices

struct WindowMinimizationContext: Sendable {
    var applications: [WindowProcessIdentity]
    var screens: [CGRect]
    var focusedPID: Int32?
    var eligibleWindowIDs: Set<UInt32>?
    var deadline: TimeInterval
}

struct WindowMinimizationOutcome: Sendable {
    var ownedCount: Int
    var failures: Int
    var focus: WindowProcessIdentity?
}

/// All retained AX objects and their ownership bookkeeping stay on the service's serial queue.
final class AXWindowMinimizer: @unchecked Sendable {
    private struct Target {
        let process: WindowProcessIdentity
        let surface: VisibleWindowSurface
        let window: AXUIElement
        let wasFocused: Bool
    }

    private let queue: DispatchQueue
    private var owned: [Target] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func minimize(context: WindowMinimizationContext,
                  cancellation: WindowVisibilityCancellation) -> WindowMinimizationOutcome {
        dispatchPrecondition(condition: .onQueue(queue))
        pruneClosedTargets()
        guard AccessibilityPermission.isTrusted, !cancellation.isCancelled else {
            return .init(ownedCount: owned.count, failures: cancellation.isCancelled ? 0 : 1)
        }
        let surfaces = visibleSurfaces(screens: context.screens).filter {
            context.eligibleWindowIDs?.contains($0.id) ?? true
        }
        var access = WindowVisibilityAXAccess(cancellation: cancellation, deadline: context.deadline)
        var failures = 0
        var pending: [Target] = []
        for process in context.applications {
            guard access.isAvailable else { break }
            let candidates = surfaces.filter { $0.pid == process.pid }
            guard !candidates.isEmpty, process.isCurrent() else { continue }
            guard let windows = access.windows(pid: process.pid) else { failures += 1; continue }
            let matched = matches(windows: windows, surfaces: candidates, access: &access)
            failures += minimize(matched, process: process,
                                 focusedSurface: process.pid == context.focusedPID ? candidates.first?
                                     .id : nil,
                                 access: &access, pending: &pending)
        }
        if !access.isAvailable, !cancellation.isCancelled {
            failures += 1
        }
        let confirmed = confirm(pending, minimized: true, deadline: context.deadline)
        owned.append(contentsOf: confirmed)
        failures += pending.count - confirmed.count
        return .init(ownedCount: owned.count, failures: failures)
    }

    func restore(activateOriginal: Bool, deadline: TimeInterval,
                 cancellation: WindowVisibilityCancellation) -> WindowMinimizationOutcome {
        dispatchPrecondition(condition: .onQueue(queue))
        guard AccessibilityPermission.isTrusted else { return .init(ownedCount: owned.count, failures: 1) }
        var access = WindowVisibilityAXAccess(cancellation: cancellation, deadline: deadline)
        var remaining: [Target] = []
        var pending: [Target] = []
        var failures = 0
        let currentSurfaces = AXQuery.copyWindowList([.optionAll], kCGNullWindowID)
        var liveWindows: [Int32: [AXUIElement]] = [:]
        for target in owned.reversed() {
            guard access.isAvailable else { remaining.append(target); continue }
            switch restoreReadiness(
                target,
                surfaces: currentSurfaces,
                windows: &liveWindows,
                access: &access
            ) {
            case .discard: continue
            case .unavailable:
                failures += 1
                remaining.append(target)
                continue
            case .ready: break
            }
            guard target.process.isCurrent() else { continue }
            remaining.append(target)
            if access.requestMinimized(false, window: target.window) {
                pending.append(target)
            } else {
                failures += 1
            }
        }
        if !access.isAvailable, !cancellation.isCancelled {
            failures += 1
        }
        let confirmed = confirm(pending, minimized: false, deadline: deadline)
        failures += pending.count - confirmed.count
        owned = remaining.reversed().filter { target in
            !confirmed.contains { CFEqual($0.window, target.window) && $0.process == target.process }
        }
        return .init(ownedCount: owned.count, failures: failures,
                     focus: restoredFocus(confirmed.last(where: \.wasFocused),
                                          requested: activateOriginal, cancellation: cancellation,
                                          deadline: deadline))
    }

    private func confirm(_ targets: [Target], minimized: Bool, deadline: TimeInterval) -> [Target] {
        let reads: [(TimeInterval) -> Bool?] = targets.map { target in
            { WindowVisibilityAXAccess.minimizedState(of: target.window, timeout: $0) }
        }
        let confirmed = WindowMinimizationConfirmation.confirm(expected: minimized, reads: reads,
                                                               deadline: .init(time: deadline))
        return targets.enumerated().compactMap { confirmed.contains($0.offset) ? $0.element : nil }
    }

    private func restoredFocus(_ focus: Target?, requested: Bool,
                               cancellation: WindowVisibilityCancellation,
                               deadline: TimeInterval) -> WindowProcessIdentity? {
        var access = WindowVisibilityAXAccess(cancellation: cancellation, deadline: deadline)
        guard requested, let focus, focus.process.isCurrent(), access.isAvailable else { return nil }
        access.raise(focus.window)
        return focus.process
    }

    private func minimize(_ targets: [(AXUIElement, VisibleWindowSurface)], process: WindowProcessIdentity,
                          focusedSurface: UInt32?, access: inout WindowVisibilityAXAccess,
                          pending: inout [Target]) -> Int {
        var failures = 0
        for (window, surface) in targets {
            guard access.isAvailable else { break }
            guard process.isCurrent(), isStillVisible(surface),
                  access.bool(kAXMinimizedAttribute, of: window) == false,
                  access.bool("AXFullScreen", of: window) == false,
                  access.isSettable(kAXMinimizedAttribute, of: window) else { continue }
            owned.removeAll { $0.process == process && CFEqual($0.window, window) }
            guard owned.count + pending.count < 100 else { failures += 1; break }
            guard process.isCurrent() else { continue }
            if access.requestMinimized(true, window: window) {
                pending.append(.init(process: process, surface: surface, window: window,
                                     wasFocused: surface.id == focusedSurface))
            } else {
                failures += 1
            }
        }
        return failures
    }

    private enum RestoreReadiness { case ready, discard, unavailable }

    private func restoreReadiness(_ target: Target, surfaces: [[String: Any]],
                                  windows: inout [Int32: [AXUIElement]],
                                  access: inout WindowVisibilityAXAccess) -> RestoreReadiness {
        guard target.process.isCurrent(), surfaces.contains(where: {
            ($0[kCGWindowNumber as String] as? UInt32) == target.surface.id
                && ($0[kCGWindowOwnerPID as String] as? Int32) == target.process.pid
        }) else { return .discard }
        if windows[target.process.pid] == nil {
            guard let current = access.windows(pid: target.process.pid) else { return .unavailable }
            windows[target.process.pid] = current
        }
        guard windows[target.process.pid]?.contains(where: { CFEqual($0, target.window) }) == true else {
            return .discard
        }
        guard let minimized = access.bool(kAXMinimizedAttribute, of: target.window)
        else { return .unavailable }
        guard minimized else { return .discard }
        guard let fullscreen = access.bool("AXFullScreen", of: target.window) else { return .unavailable }
        return fullscreen ? .discard : .ready
    }

    func discard() {
        dispatchPrecondition(condition: .onQueue(queue))
        owned.removeAll()
    }

    private func pruneClosedTargets() {
        guard !owned.isEmpty else { return }
        let surfaces = AXQuery.copyWindowList([.optionAll], kCGNullWindowID)
        owned.removeAll { target in
            !target.process.isCurrent() || !surfaces.contains {
                ($0[kCGWindowNumber as String] as? UInt32) == target.surface.id
                    && ($0[kCGWindowOwnerPID as String] as? Int32) == target.process.pid
            }
        }
    }

    private func matches(windows: [AXUIElement], surfaces: [VisibleWindowSurface],
                         access: inout WindowVisibilityAXAccess) -> [(AXUIElement, VisibleWindowSurface)] {
        var found: [(AXUIElement, Int)] = []
        for window in windows {
            guard access.isAvailable else { break }
            guard access.string(kAXRoleAttribute, of: window) == kAXWindowRole,
                  access.string(kAXSubroleAttribute, of: window) == kAXStandardWindowSubrole,
                  let frame = access.frame(of: window) else { continue }
            let title = access.string(kAXTitleAttribute, of: window)
            if let index = VisibleWindowSurface.matchingIndex(frame: frame, title: title, in: surfaces) {
                found.append((window, index))
            }
        }
        guard access.isAvailable else { return [] }
        // Same-frame AX windows on other Spaces must not become an arbitrary fallback.
        let counts = Dictionary(grouping: found, by: { $0.1 }).mapValues(\.count)
        return found.compactMap { window, index in
            counts[index] == 1 ? (window, surfaces[index]) : nil
        }
    }

    private func visibleSurfaces(screens: [CGRect]) -> [VisibleWindowSurface] {
        AXQuery.copyWindowList([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            .prefix(1000).compactMap { info in
                guard info[kCGWindowLayer as String] as? Int == 0,
                      info[kCGWindowIsOnscreen as String] as? Bool == true,
                      let id = info[kCGWindowNumber as String] as? UInt32,
                      let pid = info[kCGWindowOwnerPID as String] as? Int32,
                      let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                      let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                      frame.width > 0, frame.height > 0,
                      screens.contains(where: { $0.intersects(frame) }),
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
                return .init(id: id, pid: pid, frame: frame, title: info[kCGWindowName as String] as? String)
            }
    }

    private func isStillVisible(_ target: VisibleWindowSurface) -> Bool {
        AXQuery.copyWindowList([.optionIncludingWindow], target.id).contains { info in
            info[kCGWindowNumber as String] as? UInt32 == target.id
                && info[kCGWindowOwnerPID as String] as? Int32 == target.pid
                && info[kCGWindowIsOnscreen as String] as? Bool == true
        }
    }
}
