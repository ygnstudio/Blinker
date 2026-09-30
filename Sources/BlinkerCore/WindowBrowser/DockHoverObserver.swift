import AppKit
import ApplicationServices

public struct DockHoverTarget {
    public let pid: pid_t
    public let frame: CGRect
}

/// Observe Dock selection changes; no screen-wide mouse polling or click interception.
public final class DockHoverObserver: @unchecked Sendable {
    public var onHover: ((DockHoverTarget) -> Void)?
    private let queue = DispatchQueue(label: "com.ygnstudio.blinker.dock", qos: .utility)
    private var observer: AXObserver?
    private var dockList: AXUIElement?
    private var dockPID: pid_t?
    private var timer: Timer?
    private var revision = UUID()

    public init() {}

    public func start() {
        stop()
        reconnect()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.reconnect()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        revision = UUID()
        disconnect()
    }

    private func disconnect() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        dockList = nil
        dockPID = nil
    }

    private func reconnect() {
        guard AccessibilityPermission.isTrusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
              .first
        else { return }
        let pid = dock.processIdentifier
        let generation = revision
        queue.async { [weak self] in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.08)
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
                  let list = (children as? [AXUIElement])?.first(where: {
                      AXQuery.stringAttribute($0, kAXRoleAttribute) == kAXListRole
                  }) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, revision == generation else { return }
                if dockPID == pid, let old = dockList, CFEqual(old, list) {
                    return
                }
                disconnect()
                var newObserver: AXObserver?
                let callback: AXObserverCallback = { _, _, _, context in
                    guard let context else { return }
                    let owner = Unmanaged<DockHoverObserver>.fromOpaque(context).takeUnretainedValue()
                    owner.selectionChanged()
                }
                guard AXObserverCreate(pid, callback, &newObserver) == .success,
                      let newObserver else { return }
                let context = Unmanaged.passUnretained(self).toOpaque()
                guard AXObserverAddNotification(newObserver, list,
                                                kAXSelectedChildrenChangedNotification as CFString,
                                                context) == .success else { return }
                observer = newObserver
                dockList = list
                dockPID = pid
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
            }
        }
    }

    private func selectionChanged() {
        guard let list = dockList else { return }
        let generation = revision
        queue.async { [weak self] in
            var selected: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXSelectedChildrenAttribute as CFString, &selected) ==
                .success,
                let item = (selected as? [AXUIElement])?.first,
                AXQuery.stringAttribute(item, kAXSubroleAttribute) == "AXApplicationDockItem",
                let axFrame = AXQuery.elementFrame(item) else { return }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &value) == .success,
                  let url = value as? URL else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, revision == generation, NSEvent.pressedMouseButtons == 0 else { return }
                let frame = AXQuery.appKitFrame(fromAXRect: axFrame)
                guard frame.contains(NSEvent.mouseLocation),
                      let app = NSWorkspace.shared.runningApplications.first(where: {
                          $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
                      }), !SessionPause.shared.contains(app.bundleIdentifier ?? "") else { return }
                onHover?(DockHoverTarget(pid: app.processIdentifier, frame: frame))
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
    }
}
