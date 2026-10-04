import AppKit
import ApplicationServices

/// Listen-only: all original Dock events reach the system unchanged. AX IPC is
/// confined to a serial worker and never holds up the event-tap thread.
final class DockClickEventObserver: @unchecked Sendable {
    private struct HitRequest {
        let ticket: UUID
        let dockPID: Int32
        let frontmostPID: Int32?
    }

    private let host = EventTapThreadHost(threadName: "com.ygnstudio.blinker.dock-click-tap")
    private let worker = DispatchQueue(label: "com.ygnstudio.blinker.dock-click-hit", qos: .userInitiated)
    private let lock = NSLock()
    private var gesture = DockClickGesture()
    private var frontmostPID: Int32?
    private var dockPID: Int32?
    private var candidateRegions: [CGRect] = []
    private let onClick: @Sendable (DockClickCandidate) -> Void

    init(onClick: @escaping @Sendable (DockClickCandidate) -> Void) {
        self.onClick = onClick
    }

    func setFrontmostPID(_ pid: Int32?) {
        lock.withLock { frontmostPID = pid }
    }

    func setCandidateRegions(_ regions: [CGRect]) {
        lock.withLock {
            candidateRegions = regions
            gesture.cancel()
        }
    }

    func start(dockPID: Int32, maximumPressDuration: TimeInterval) -> Bool {
        stop()
        lock.withLock {
            self.dockPID = dockPID
            gesture = DockClickGesture(maximumPressDuration: maximumPressDuration)
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .otherMouseDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        return host.start(mask: mask, options: .listenOnly, callback: { _, type, event, context in
            if let context {
                let owner = Unmanaged<DockClickEventObserver>.fromOpaque(context).takeUnretainedValue()
                owner.receive(type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    }

    func stop() {
        lock.withLock {
            gesture.cancel()
            dockPID = nil
        }
        host.stop()
    }

    func isCurrent(_ ticket: UUID) -> Bool {
        lock.withLock { dockPID != nil && gesture.ticket == ticket }
    }

    private func receive(_ type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.withLock { gesture.cancel() }
            host.enableTap()
            return
        }
        let input = DockClickEventInput(event, receivedAt: ProcessInfo.processInfo.systemUptime)
        switch type {
        case .leftMouseDown:
            let request: HitRequest? = lock.withLock {
                guard let dockPID, let ticket = gesture.begin(at: input.point, time: input.receivedAt,
                                                              frontmostPID: frontmostPID,
                                                              isPlainSingleClick: input.isPlain && input
                                                                  .isSingle,
                                                              candidateRegions: candidateRegions)
                else { return nil }
                return HitRequest(ticket: ticket, dockPID: dockPID, frontmostPID: frontmostPID)
            }
            if let request {
                resolve(at: input.point, ticket: request.ticket,
                        dockPID: request.dockPID, frontmostPID: request.frontmostPID)
            }
        case .leftMouseUp:
            let candidate = lock.withLock {
                gesture.end(at: input.point, time: input.receivedAt,
                            isPlainSingleClick: input.isPlain && input.isSingle)
            }
            if let candidate {
                onClick(candidate)
            }
        case .flagsChanged where input.isPlain:
            break
        default:
            lock.withLock { gesture.cancel() }
        }
    }

    private func resolve(at point: CGPoint, ticket: UUID, dockPID: Int32, frontmostPID: Int32?) {
        worker.async { [weak self] in
            guard let self, isCurrent(ticket) else { return }
            let windows = Self.visibleWindows(pid: frontmostPID)
            lock.withLock { self.gesture.snapshot(windows, for: ticket) }
            let hit = Self.hit(at: point, dockPID: dockPID)
            let candidate = lock.withLock { self.gesture.resolve(hit, for: ticket) }
            if let candidate {
                onClick(candidate)
            }
        }
    }

    private static func visibleWindows(pid: Int32?) -> Set<UInt32> {
        guard let pid else { return [] }
        let surfaces = AXQuery.copyWindowList([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return Set(surfaces.compactMap { surface in
            guard surface[kCGWindowOwnerPID as String] as? Int32 == pid,
                  surface[kCGWindowLayer as String] as? Int == 0,
                  surface[kCGWindowIsOnscreen as String] as? Bool == true else { return nil }
            return surface[kCGWindowNumber as String] as? UInt32
        })
    }

    private static func hit(at point: CGPoint, dockPID: Int32) -> DockClickHit? {
        guard AccessibilityPermission.isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var item: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &item) == .success,
              let item else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(item, &owner) == .success, owner == dockPID else { return nil }
        AXUIElementSetMessagingTimeout(item, 0.08)
        guard AXQuery.stringAttribute(item, kAXSubroleAttribute) == "AXApplicationDockItem",
              let frame = AXQuery.elementFrame(item), frame.contains(point) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &value) == .success,
              let url = value as? URL, url.isFileURL else { return nil }
        return DockClickHit(applicationURL: url.standardizedFileURL, frame: frame)
    }

    deinit { host.stop() }
}
