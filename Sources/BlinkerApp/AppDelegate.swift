import AppKit
import BlinkerCore
import Combine
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
/// the hover overlay, plus the window-management helpers (front-window
/// executor, drag-to-snap snapper, global hotkeys).
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject {
    let ruleStore = RuleStore()
    let hoverOverlaySettingsStore = HoverOverlaySettingsStore()
    /// Named window-layout workspaces for the window-management tab.
    let workspaceStore = WorkspaceStore()

    /// Executes window actions on the frontmost window; shared by the
    /// window-management tab and the global hotkeys.
    private(set) lazy var frontWindowPerformer = FrontWindowActionPerformer(
        performer: DefaultWindowActionPerformer()
    )

    /// Global hotkeys; independent of click interception, always available.
    private(set) lazy var hotkeyManager = HotkeyManager(frontWindowPerformer: frontWindowPerformer)

    @Published private(set) var isIntercepting = false
    @Published private(set) var status: InterceptorStatus = .checking

    private var interceptor: TrafficLightInterceptor?
    private var windowSnapper: WindowSnapper?
    private var hoverOverlay: HoverOverlayController?
    private var retryTimer: Timer?
    private var statusItem: NSStatusItem?
    private var preferencesCancellable: AnyCancellable?
    private var hasPromptedForPermission = false
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "app")

    func applicationDidFinishLaunching(_: Notification) {
        // Menu bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        // The HUD lives in Core and cannot observe AppPreferences; mirror
        // the language choice so overlay text matches the settings UI.
        OverlayL10n.preferEnglish = AppPreferences.shared.isEnglish
        observeAccessibilityTrustChanges()
        setupStatusItem()
        attemptStartInterceptor()
        wireHoverToggleHotkey()
    }

    /// The ⌃⌥H global hotkey (configurable) flips hover enlargement without
    /// a trip to the settings window.
    private func wireHoverToggleHotkey() {
        hotkeyManager.onToggleHoverOverlay = { [weak self] in
            guard let self else { return }
            var settings = hoverOverlaySettingsStore.snapshot
            settings.isEnabled.toggle()
            applyHoverOverlaySettings(settings)
        }
    }

    // MARK: - Status item

    /// The menu bar icon is the app's front door: a plain left click opens
    /// the settings window; the context menu (right click) only carries the
    /// live status row, settings and quit — interception pause lives in the
    /// settings' General tab instead of the menu.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "circle.circle",
            accessibilityDescription: "Blinker"
        )
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // The action must fire for secondary clicks too, otherwise the
        // context menu can never be shown.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || (event?.type == .otherMouseUp && event?.modifierFlags.contains(.control) == true)
        if isSecondaryClick {
            showContextMenu()
        } else {
            openSettings()
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.delegate = self

        let statusRow = NSMenuItem()
        let hostingView = NSHostingView(rootView: InterceptorStatusRow(appDelegate: self))
        // Size to the localized status text (with a floor), so longer
        // labels never clip inside the menu row.
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(220, ceil(fittingSize.width)), height: max(24, ceil(fittingSize.height)))
        )
        statusRow.view = hostingView
        menu.addItem(statusRow)
        menu.addItem(.separator())

        if status == .tapFailed {
            let retryItem = NSMenuItem(
                title: tr("重试启动拦截", "Retry Starting Interception"),
                action: #selector(retryInterceptorClicked),
                keyEquivalent: ""
            )
            retryItem.target = self
            menu.addItem(retryItem)
        }

        let settingsItem = NSMenuItem(
            title: tr("设置…", "Settings…"),
            action: #selector(openSettingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: tr("退出 Blinker", "Quit Blinker"),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        // The menu only opens on right click via the action handler, so it
        // is attached just for this invocation and detached on close —
        // otherwise it would also swallow the plain left click.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    @objc private func retryInterceptorClicked() {
        attemptStartInterceptor()
    }

    func menuDidClose(_: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func openSettingsClicked() {
        openSettings()
    }

    // MARK: - Settings window

    private var settingsWindow: NSWindow?

    /// Shows the settings window, creating it on first open. A plain NSWindow
    /// hosting the SwiftUI settings screen — deliberately not the SwiftUI
    /// `Settings` scene, whose private `showSettingsWindow:` selector is
    /// unreliable to invoke from AppKit in an accessory app.
    func openSettings() {
        bringToFront()
        if settingsWindow == nil {
            let rootView = SettingsView(
                ruleStore: ruleStore,
                hoverSettingsStore: hoverOverlaySettingsStore,
                onApplyHoverSettings: applyHoverOverlaySettings,
                hotkeyManager: hotkeyManager,
                workspaceStore: workspaceStore,
                onSnapEnabledChange: applySnapEnabled,
                appDelegate: self
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            // System Settings–style chrome: the content fills the window and
            // the traffic-light buttons float on the sidebar's own material.
            // The pane name lives inside the detail column, so the window
            // title stays hidden. The window keeps its standard opaque
            // background — on macOS 26+ the sidebar's Liquid Glass and the
            // toolbar materials are provided by the system automatically.
            window.title = "Blinker"
            window.titleVisibility = .hidden
            // Pre-26: draw no titlebar background so the sidebar material
            // runs under the traffic lights. 26+: leave it unset so the
            // system paints its Liquid Glass titlebar/toolbar material.
            if #unavailable(macOS 26.0) {
                window.titlebarAppearsTransparent = true
            }
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert(.miniaturizable)
            window.setContentSize(NSSize(width: 860, height: 560))
            window.contentMinSize = NSSize(width: 720, height: 460)
            window.center()
            window.isReleasedWhenClosed = false
            // Normal level: `bringToFront()` handles the initial fronting;
            // a floating window would permanently cover other apps' windows.
            window.appearance = AppPreferences.shared.nsAppearance
            settingsWindow = window
            observeWindowVisibility()
            observePreferenceChanges()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Keeps the settings window chrome in sync with the General tab:
    /// `NSAppearance` lives on the AppKit side, so SwiftUI's
    /// `preferredColorScheme` alone leaves the titlebar one step behind the
    /// content. Language needs no window-side work anymore — the SwiftUI
    /// sidebar re-renders itself, and the HUD reads the mirrored
    /// `OverlayL10n` preference updated here.
    private func observePreferenceChanges() {
        preferencesCancellable = AppPreferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the new value lands; reading
                // the preference on the next turn picks up the fresh value.
                DispatchQueue.main.async {
                    OverlayL10n.preferEnglish = AppPreferences.shared.isEnglish
                }
                self?.settingsWindow?.appearance = AppPreferences.shared.nsAppearance
            }
    }

    /// Activates the app so newly opened windows (settings) appear on top.
    /// Menu bar apps run with the `.accessory` policy and are not activated
    /// automatically when they open a window.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Safety net: whenever the settings window becomes key, pull the app
    /// to the front again. Covers paths that bypass `bringToFront()`.
    /// Scoped to the settings window only — activating on *any* key window
    /// would aggressively steal focus from other apps.
    private func observeWindowVisibility() {
        guard let settingsWindow else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: settingsWindow,
            queue: .main
        ) { [weak self] _ in
            self?.bringToFront()
        }
    }

    /// Starts (or restarts, e.g. after the permission was granted) interception.
    func attemptStartInterceptor() {
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

    /// Stops the permission-retry poll; called once interception is up (or
    /// already up), whatever path got it there.
    private func cancelPermissionRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// The no-permission branch of `attemptStartInterceptor`: surface the
    /// state, prompt once, and poll until access is granted.
    private func handleMissingAccessibilityPermission() {
        status = .noPermission
        logger.error("accessibility permission missing")
        if !hasPromptedForPermission {
            hasPromptedForPermission = true
            AccessibilityPermission.prompt()
        }
        schedulePermissionRetry()
    }

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

        isIntercepting = true
        status = .running
        cancelPermissionRetry()
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
        windowSnapper?.stop()
        windowSnapper = nil
        hoverOverlay?.stop()
        hoverOverlay = nil
        isIntercepting = false
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
