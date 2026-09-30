import AppKit
import ApplicationServices

/// Tracks focus changes inside the frontmost app, including two windows of the
/// same app. All AX work stays off main; observers are attached to the main run loop.
final class ActiveWindowObserver: @unchecked Sendable {
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "com.ygnstudio.blinker.focus-observer", qos: .utility)
    private var pid: pid_t?
    private var observer: AXObserver?
    private var revision = UUID()

    func observe(_ process: pid_t?) {
        guard process != pid else { return }
        stop()
        guard let process, AccessibilityPermission.isTrusted else { return }
        pid = process
        let token = revision
        queue.async { [weak self] in
            let app = AXUIElementCreateApplication(process)
            AXUIElementSetMessagingTimeout(app, 0.08)
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, context in
                guard let context else { return }
                Unmanaged<ActiveWindowObserver>.fromOpaque(context).takeUnretainedValue().onChange?()
            }
            guard AXObserverCreate(process, callback, &created) == .success, let created,
                  let self else { return }
            let status = AXObserverAddNotification(
                created,
                app,
                kAXFocusedWindowChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard status == .success else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, revision == token else { return }
                observer = created
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            }
        }
    }

    func stop() {
        revision = UUID()
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        pid = nil
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
    }
}
