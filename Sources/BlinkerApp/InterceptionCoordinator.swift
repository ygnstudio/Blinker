import AppKit
import BlinkerCore
import Combine
import os

/// Lifecycle state of the click interceptor, shown in the menu bar menu.
enum InterceptorStatus {
    case checking
    case running
    case noPermission
    case tapFailed
    case paused

    var localizedLabel: String {
        switch self {
        case .checking: String(localized: "检查辅助功能权限…")
        case .running: String(localized: "已启用")
        case .noPermission: String(localized: "未授权辅助功能")
        case .tapFailed: String(localized: "事件监听启动失败")
        case .paused: String(localized: "已关闭")
        }
    }
}

/// Owns the interception stack and its lifecycle: the click interceptor,
/// the hover overlay and the drag-to-snap snapper — plus the
/// permission-retry loop and the live `status` the UI observes.
final class InterceptionCoordinator: ObservableObject {
    @Published private(set) var status: InterceptorStatus = .checking

    /// True while the click-interception stack is running; derived from
    /// `status` so the two can never disagree.
    var isIntercepting: Bool { status == .running }

    private var interceptor: TrafficLightInterceptor?
    private var windowSnapper: WindowSnapper?
    private var hoverOverlay: HoverOverlayController?
    private var retryTimer: Timer?
    private var hasPromptedForPermission = false
    private let ruleStore: RuleStore
    private let hoverOverlaySettingsStore: HoverOverlaySettingsStore
    private let workspaceStore: WorkspaceStore
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "interception")

    init(
        ruleStore: RuleStore,
        hoverOverlaySettingsStore: HoverOverlaySettingsStore,
        workspaceStore: WorkspaceStore
    ) {
        self.ruleStore = ruleStore
        self.hoverOverlaySettingsStore = hoverOverlaySettingsStore
        self.workspaceStore = workspaceStore
        observeAccessibilityTrustChanges()
    }

    /// Starts (or restarts, e.g. after the permission was granted) interception.
    func start() {
        guard interceptor == nil else {
            // Already running; still refresh the visible status. Any pending
            // permission-retry poll has served its purpose by now and must
            // not keep firing every two seconds.
            status = .running
            cancelPermissionRetry()
            return
        }
        guard AccessibilityPermission.isTrusted else {
            handleMissingAccessibilityPermission()
            return
        }
        startInterceptionStack()
    }

    /// Pauses or resumes click interception from the menu bar toggle.
    func toggle() {
        if isIntercepting {
            stop()
        } else {
            start()
        }
    }

    func stop() {
        interceptor?.stop()
        interceptor = nil
        windowSnapper?.stop()
        windowSnapper = nil
        hoverOverlay?.stop()
        hoverOverlay = nil
        status = .paused
        logger.info("interceptor stopped")
    }

    /// Persists the drag-to-snap toggle and applies it to the live snapper.
    func applySnapEnabled(_ enabled: Bool) {
        AppPreferences.shared.isSnapEnabled = enabled
        windowSnapper?.setEnabled(enabled)
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

    // MARK: - Startup

    /// Brings up the full interception stack: click interceptor, hover
    /// overlay and drag-to-snap, all sharing one permission and performer.
    private func startInterceptionStack() {
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
            settingsStore: hoverOverlaySettingsStore,
            workspacesProvider: { [weak workspaceStore] in
                workspaceStore?.workspaces.map {
                    HUDWorkspaceItem(id: $0.id, name: $0.name, windowCount: $0.entries.count)
                } ?? []
            },
            workspaceRestorer: { [weak workspaceStore] id in
                workspaceStore?.restore(id: id)
            }
        )
        overlay.start()

        self.interceptor = interceptor
        hoverOverlay = overlay

        // Drag-to-snap rides on the same permission and performer; honors
        // the persisted settings toggle from day one.
        let snapper = WindowSnapper(actionPerformer: performer)
        if snapper.start() {
            snapper.setEnabled(AppPreferences.shared.isSnapEnabled)
            windowSnapper = snapper
        } else {
            logger.error("snapper tap failed to start; drag-to-snap unavailable")
        }

        status = .running
        cancelPermissionRetry()
        logger.info("interceptor started; event tap active")
    }

    // MARK: - Permission handling

    /// The no-permission branch of `start()`: surface the state, prompt
    /// once, and poll until access is granted.
    private func handleMissingAccessibilityPermission() {
        status = .noPermission
        logger.error("accessibility permission missing")
        if !hasPromptedForPermission {
            hasPromptedForPermission = true
            AccessibilityPermission.prompt()
        }
        schedulePermissionRetry()
    }

    /// Stops the permission-retry poll; called once interception is up (or
    /// already up), whatever path got it there.
    private func cancelPermissionRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

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
        start()
    }

    /// Polls briefly until the user finishes granting access in System
    /// Settings, in case the distributed notification is missed.
    private func schedulePermissionRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if interceptor != nil {
                // Defensive: the interceptor is running, so whatever
                // started it should already have cancelled this timer.
                // Stop polling instead of spinning idly until relaunch.
                retryTimer?.invalidate()
                retryTimer = nil
                return
            }
            retryTimer?.invalidate()
            retryTimer = nil
            start()
        }
    }
}
