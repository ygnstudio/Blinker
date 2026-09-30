import AppKit
import BlinkerCore
import Combine

/// A transient, nonactivating status panel. Errors are also retained in Settings.
final class ActionFeedbackController: ObservableObject {
    static let shared = ActionFeedbackController()
    @Published private(set) var latestMessage: String?
    private var observer: NSObjectProtocol?
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: ActionFeedback.notification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let message = notification.userInfo?["message"] as? String else { return }
            self?.show(message)
        }
    }

    func show(_ message: String) {
        latestMessage = message
        dismissal?.cancel()
        let panel = panel ?? NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 72),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        let label = NSTextField(wrappingLabelWithString: message)
        label.frame = NSRect(x: 16, y: 12, width: 308, height: 48)
        background.addSubview(label)
        panel.contentView = background
        if let screen = NSScreen.screens
            .first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(
                x: screen.visibleFrame.maxX - 356,
                y: screen.visibleFrame.maxY - 16
            ))
        }
        self.panel = panel
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [
                                 .announcement: message,
                                 .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                             ])
        let dismissal = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: dismissal)
    }
}
