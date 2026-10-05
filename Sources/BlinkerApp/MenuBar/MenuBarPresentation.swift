import AppKit
import Combine
import SwiftUI

/// One presentation owner for menu bar, Dock and the configurable system panel.
@MainActor
final class MenuBarPresentation: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let item: NSStatusItem
    private let monitor: SystemStatusMonitor
    private let audio: SystemAudioController
    private let scanner: BluetoothLEScanner
    private let preferences: MenuBarPreferences
    private let onOpenApplications: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenMenuBarPage: (MenuBarSettingsPage) -> Void
    private let popover = NSPopover()
    private let charging = MenuBarChargingAnimation()
    private let scrolling = MenuBarVolumeScroll()
    private var dockWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var suspended = false
    private let originalIcon = NSApp.applicationIconImage
    private var previousPlacement: MenuBarConfiguration.Placement?

    init(item: NSStatusItem, monitor: SystemStatusMonitor, audio: SystemAudioController,
         scanner: BluetoothLEScanner,
         preferences: MenuBarPreferences, onOpenApplications: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenMenuBarPage: @escaping (MenuBarSettingsPage) -> Void) {
        self.item = item
        self.monitor = monitor
        self.audio = audio
        self.scanner = scanner
        self.preferences = preferences
        self.onOpenApplications = onOpenApplications
        self.onOpenSettings = onOpenSettings
        self.onOpenMenuBarPage = onOpenMenuBarPage
        super.init()
        popover.behavior = .transient
        popover.delegate = self
    }

    func start() {
        monitor.$snapshot.combineLatest(preferences.$configuration)
            .sink { [weak self] snapshot, configuration in
                self?.render(snapshot, configuration: configuration)
            }.store(in: &subscriptions)
        audio.onChange = { [weak monitor] in monitor?.refresh() }
        appearanceObservation = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.renderCurrent() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.suspend()
            }.store(in: &subscriptions)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.resume()
            }.store(in: &subscriptions)
        }
        center.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.renderCurrent() }
            .store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(
            for: Notification.Name("AppleInterfaceThemeChangedNotification")
        ).receive(on: RunLoop.main).sink { [weak self] _ in self?.renderCurrent() }
            .store(in: &subscriptions)
        resume()
    }

    func stop() {
        closePanel()
        suspend()
        subscriptions.removeAll()
        appearanceObservation = nil
        audio.onChange = nil
    }

    private func suspend() {
        suspended = true
        monitor.stop()
        audio.stop()
        scanner.setEnabled(false)
        charging.stop()
        scrolling.stop()
    }

    private func resume() {
        suspended = false
        monitor.start()
        audio.start()
        renderCurrent()
        if let window = popover.contentViewController?.view.window, popover.isShown {
            installScroll(in: window)
        } else if let dockWindow, dockWindow.isVisible {
            installScroll(in: dockWindow)
        }
    }

    private func renderCurrent() {
        render(monitor.snapshot, configuration: preferences.configuration)
    }

    private func render(_ snapshot: MenuBarSystemSnapshot, configuration: MenuBarConfiguration) {
        monitor.setRefreshInterval(configuration.refreshInterval)
        monitor.setReadOptions(SystemStatusReadOptions(
            includeVPN: configuration.showsVPNStatus,
            includeWiFiName: configuration.showsWiFiName,
            includeBluetoothDevices: configuration.enabledSections.contains(.bluetooth)
        ))
        if !suspended {
            // The scan only has somewhere to display while the block is visible.
            scanner.setEnabled(configuration.scansNearbyBluetoothDevices
                && configuration.enabledSections.contains(.bluetooth))
        }
        if previousPlacement != configuration.placement {
            closePanel()
            item.isVisible = configuration.showsMenuBar
            NSApp.setActivationPolicy(configuration.showsDock ? .regular : .accessory)
            if !configuration.showsDock {
                NSApp.applicationIconImage = originalIcon
            }
            previousPlacement = configuration.placement
        }
        if let button = item.button {
            // Respect the physical menu bar height; a 36 pt image must not overflow a 24 pt bar.
            let availableHeight = max(16, button.bounds.height - 2)
            let size = min(configuration.iconSize, availableHeight)
            item.length = size + 8
            button.imageScaling = .scaleProportionallyDown
            button.image = TrioIconRenderer.image(
                snapshot: snapshot,
                size: size,
                configuration: configuration
            )
            let description = "Blinker · " + snapshot.accessibilitySummary
            button.toolTip = description
            button.setAccessibilityLabel(description)
            button.setAccessibilityHelp(configuration.leftClick == .panel
                ? String(localized: "单击打开状态面板，右键打开菜单。")
                : String(localized: "单击打开应用规则，右键打开菜单。"))
            charging.update(button: button, snapshot: snapshot, configuration: configuration,
                            size: size, suspended: suspended || !configuration.showsMenuBar)
        }
        if configuration.showsDock {
            let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            NSApp.applicationIconImage = DockIconRenderer.image(
                snapshot: snapshot, configuration: configuration,
                appearance: NSAppearance(named: dark ? .darkAqua : .aqua)
            )
        }
    }

    func showPanel() {
        if popover.isShown || dockWindow?.isVisible == true {
            closePanel()
            return
        }
        monitor.refresh()
        audio.refresh()
        scanner.refresh()
        let controller = NSHostingController(rootView: SystemStatusPanel(
            monitor: monitor, audio: audio, scanner: scanner, preferences: preferences,
            onOpenApplications: { [weak self] in
                self?.closePanel()
                self?.onOpenApplications()
            }, onOpenSettings: { [weak self] in
                self?.closePanel()
                self?.onOpenSettings()
            }, onOpenMenuBarPage: { [weak self] page in
                self?.closePanel()
                self?.onOpenMenuBarPage(page)
            }
        ))
        controller.sizingOptions = [.preferredContentSize]
        if preferences.configuration.showsMenuBar, let button = item.button {
            popover.contentViewController = controller
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = controller.view.window {
                installScroll(in: window)
            }
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "系统状态")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(controller.preferredContentSize)
            window.center()
            dockWindow = window
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            installScroll(in: window)
        }
    }

    func closePanel() {
        popover.performClose(nil)
        dockWindow?.close()
        dockWindow = nil
        scrolling.stop()
    }

    func popoverDidClose(_: Notification) {
        popover.contentViewController = nil
        scrolling.stop()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === dockWindow else { return }
        scrolling.stop()
        dockWindow = nil
    }

    private func installScroll(in window: NSWindow) {
        scrolling.start(window: window, audio: audio, preferences: preferences)
    }
}
