import AppKit
import BlinkerCore
import os
import SwiftUI

/// Lifecycle state of the click interceptor, shown in the menu bar menu.
enum InterceptorStatus {
    case checking
    case running
    case noPermission
    case tapFailed
    case paused

    var localizedLabel: String {
        switch self {
        case .checking: tr("检查辅助功能权限…", "Checking accessibility permission…")
        case .running: tr("拦截运行中", "Interception running")
        case .noPermission: tr("未授权辅助功能", "Accessibility not granted")
        case .tapFailed: tr("事件监听启动失败", "Event tap failed to start")
        case .paused: tr("已暂停", "Paused")
        }
    }
}

/// Owns the long-lived app state: the rule store, the event interceptor and
/// the hover overlay.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let ruleStore = RuleStore()
    let hoverOverlaySettingsStore = HoverOverlaySettingsStore()

    @Published private(set) var isIntercepting = false
    @Published private(set) var status: InterceptorStatus = .checking

    private var interceptor: TrafficLightInterceptor?
    private var hoverOverlay: HoverOverlayController?
    private var retryTimer: Timer?
    private var hasPromptedForPermission = false
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "app")

    func applicationDidFinishLaunching(_: Notification) {
        // Menu bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        observeWindowVisibility()
        observeAccessibilityTrustChanges()
        attemptStartInterceptor()
    }

    /// Activates the app so newly opened windows (settings) appear on top.
    /// Menu bar apps run with the `.accessory` policy and are not activated
    /// automatically when they open a window.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Safety net: whenever any window of the app becomes key, pull the
    /// app to the front again. Covers paths that bypass `bringToFront()`.
    private func observeWindowVisibility() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringToFront()
        }
    }

    /// Starts (or restarts, e.g. after the permission was granted) interception.
    func attemptStartInterceptor() {
        guard interceptor == nil else {
            // Already running; still refresh the visible status.
            status = .running
            return
        }
        guard AccessibilityPermission.isTrusted else {
            status = .noPermission
            logger.error("accessibility permission missing")
            if !hasPromptedForPermission {
                hasPromptedForPermission = true
                AccessibilityPermission.prompt()
            }
            schedulePermissionRetry()
            return
        }

        let engine = RuleEngine { [weak ruleStore] in ruleStore?.snapshot ?? [] }
        let performer = DefaultWindowActionPerformer()
        let interceptor = TrafficLightInterceptor(ruleEngine: engine, actionPerformer: performer)
        guard interceptor.start() else {
            status = .tapFailed
            logger.error("event tap creation failed")
            schedulePermissionRetry()
            return
        }

        // The overlay only works while the interceptor's tap is active too.
        let overlay = HoverOverlayController(
            ruleEngine: engine,
            actionPerformer: performer,
            settingsStore: hoverOverlaySettingsStore
        )
        overlay.start()

        self.interceptor = interceptor
        hoverOverlay = overlay
        isIntercepting = true
        status = .running
        logger.info("interceptor started; event tap active")
    }

    /// Pauses or resumes click interception from the menu bar toggle.
    func toggleInterception() {
        if isIntercepting {
            stopInterceptor()
        } else {
            attemptStartInterceptor()
        }
    }

    func stopInterceptor() {
        interceptor?.stop()
        interceptor = nil
        hoverOverlay?.stop()
        hoverOverlay = nil
        isIntercepting = false
        status = .paused
        logger.info("interceptor stopped")
    }

    /// Persists hover overlay settings and pushes them to the live overlay
    /// controller (when running) so visible panels refresh immediately.
    func applyHoverOverlaySettings(_ settings: HoverOverlaySettings) {
        guard let hoverOverlay else {
            hoverOverlaySettingsStore.update(settings)
            return
        }
        hoverOverlay.updateConfiguration(settings)
    }

    // MARK: - Permission observation

    /// The system posts this distributed notification whenever the
    /// Accessibility trust list changes (user grants or revokes access).
    private func observeAccessibilityTrustChanges() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityTrustDidChange),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }

    @objc private func accessibilityTrustDidChange() {
        logger.info("accessibility trust list changed; re-evaluating")
        retryTimer?.invalidate()
        retryTimer = nil
        attemptStartInterceptor()
    }

    /// Polls briefly until the user finishes granting access in System
    /// Settings, in case the distributed notification is missed.
    private func schedulePermissionRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, interceptor == nil else { return }
            retryTimer?.invalidate()
            retryTimer = nil
            attemptStartInterceptor()
        }
    }
}

/// Live status row shown at the top of the menu bar menu.
struct InterceptorStatusRow: View {
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appDelegate.isIntercepting ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(appDelegate.status.localizedLabel)
                .font(.callout)
        }
    }
}
