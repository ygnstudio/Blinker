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
        observeWindowVisibility()
        observeAccessibilityTrustChanges()
        setupStatusItem()
        attemptStartInterceptor()
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 30)
        statusRow.view = hostingView
        menu.addItem(statusRow)
        menu.addItem(.separator())

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
            let controller = SettingsTabViewController(
                ruleStore: ruleStore,
                hoverSettingsStore: hoverOverlaySettingsStore,
                onApplyHoverSettings: applyHoverOverlaySettings,
                hotkeyManager: hotkeyManager,
                workspaceStore: workspaceStore,
                onSnapEnabledChange: applySnapEnabled,
                appDelegate: self
            )
            let window = NSWindow(contentViewController: controller)
            window.title = tr("Blinker 设置", "Blinker Settings")
            window.styleMask.insert(.miniaturizable)
            window.setContentSize(NSSize(width: 640, height: 480))
            window.contentMinSize = NSSize(width: 640, height: 420)
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.appearance = AppPreferences.shared.nsAppearance
            if #available(macOS 26.0, *) {
                // Liquid Glass backdrop: let the SwiftUI glass pane in each
                // tab blur what is behind the window. Earlier systems keep
                // the standard opaque window.
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            settingsWindow = window
            observePreferenceChanges()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Keeps the settings window chrome in sync with the General tab: the
    /// window title and `NSAppearance` live on the AppKit side, so SwiftUI's
    /// `preferredColorScheme` alone leaves the titlebar (and the in-titlebar
    /// tab row) one step behind the content.
    private func observePreferenceChanges() {
        preferencesCancellable = AppPreferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let window = self?.settingsWindow else { return }
                window.title = tr("Blinker 设置", "Blinker Settings")
                window.appearance = AppPreferences.shared.nsAppearance
            }
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
