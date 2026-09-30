import AppKit
import BlinkerCore
import Combine
import SwiftUI

@MainActor
final class WindowBrowserController: ObservableObject {
    let preferences = WindowBrowserPreferences()
    let catalog = WindowCatalog()
    let thumbnails = WindowThumbnailStore()
    @Published private(set) var windows: [BrowserWindow] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var shortcutAvailable = true
    @Published private(set) var isOpen = false
    @Published private(set) var dockMode = false
    private var selection = WindowBrowserSelection()
    private let presentation = WindowBrowserPresentation()
    private var panel: WindowBrowserPanel? {
        presentation.panel
    }

    private var pidFilter: pid_t?
    private var anchor: CGRect?
    private var display = CGRect.zero
    private var mouseAtPresentation = CGPoint.zero
    private var sessionID = UUID()
    private var holdingOption = false
    private var pendingCommit = false
    private var initialDirection = 0
    private var invokingPID: pid_t?
    private var paused = false
    private let hotkeys = WindowSwitcherHotkeys()
    private let dock = DockHoverObserver()
    private var dockDelay: Task<Void, Never>?
    private var leaveTimer: Timer?
    private var outsideSince: Date?
    private var refreshTimer: Timer?
    private var localMonitor: Any?
    private var visibleIDs = Set<UUID>()
    private var thumbnailRefreshTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    var usesThumbnails: Bool {
        preferences.thumbnailsEnabled && thumbnails.permissionGranted
    }

    var previewScale: CGFloat {
        preferences.previewScale
    }

    var presentationSize: CGSize {
        presentationFrame().size
    }

    var layout: WindowBrowserLayout {
        WindowBrowserGeometry.previewLayout(windowCount: windows.count, scale: preferences.previewScale,
                                            screenSize: display.size)
    }

    var selectedWindow: BrowserWindow? {
        windows.first { $0.id == selectedID }
    }

    var presentationID: UUID {
        sessionID
    }

    func setVisible(_ id: UUID, visible: Bool, session: UUID) {
        guard isOpen, session == sessionID else { return }
        if visible {
            visibleIDs.insert(id)
        } else {
            visibleIDs.remove(id)
        }
        scheduleThumbnailRefresh()
    }

    private func scheduleThumbnailRefresh() {
        thumbnailRefreshTask?.cancel()
        thumbnailRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self, isOpen else { return }
            refreshThumbnails()
        }
    }

    func start() {
        thumbnails.canCapture = { [weak catalog] id in await catalog?.canCapture(id) ?? false }
        hotkeys.onCycle = { [weak self] direction in self?.cycleShortcut(direction) }
        hotkeys.onRelease = { [weak self] in self?.releaseOption() }
        dock.onHover = { [weak self] target in self?.scheduleDock(target) }
        preferences.runtimeChanges.sink { [weak self] in
            DispatchQueue.main.async { self?.applyPreferences() }
        }.store(in: &subscriptions)
        preferences.$previewScale.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.objectWillChange.send()
                if self.isOpen {
                    self.panel?.setFrame(self.presentationFrame(), display: true)
                    self.updateCornerRadius()
                    self.panel?.invalidateShadow()
                }
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: WindowBrowserRequest.showApplication)
            .sink { [weak self] notification in
                guard let pid = notification.userInfo?["pid"] as? pid_t else { return }
                self?.show(pid: pid)
            }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if isOpen, panel?.isKeyWindow != true {
                    dismiss()
                }
                if !paused, preferences.switcherEnabled || preferences.dockEnabled {
                    Task { await self.catalog.refresh() }
                }
            }.store(in: &subscriptions)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .flagsChanged,
        ]) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        applyPreferences()
        Task { await catalog.refresh() }
    }

    func setPaused(_ value: Bool) {
        paused = value; applyPreferences()
    }

    private func applyPreferences() {
        dismiss()
        if !preferences.thumbnailsEnabled {
            thumbnails.clear()
        }
        hotkeys.stop()
        dock.stop()
        catalog.stopTracking()
        catalog.includeTabs = preferences.includeTabs
        guard !paused else { return }
        shortcutAvailable = !preferences.switcherEnabled || hotkeys.start()
        if preferences.dockEnabled {
            dock.start()
        }
    }

    func show(pid: pid_t? = nil) {
        begin(pid: pid, anchor: nil, keyboard: false, direction: 0)
    }

    private func cycleShortcut(_ direction: Int) {
        guard !paused else { return }
        if isOpen, holdingOption {
            if windows.isEmpty {
                initialDirection += direction
            } else {
                move(direction)
            }
            return
        }
        begin(pid: nil, anchor: nil, keyboard: true, direction: direction)
    }

    private func begin(pid: pid_t?, anchor: CGRect?, keyboard: Bool, direction: Int) {
        dismiss()
        guard AccessibilityPermission.isTrusted else { ActionFeedback.report(.permissionRequired); return }
        sessionID = UUID()
        let token = sessionID
        pidFilter = pid
        self.anchor = anchor
        dockMode = anchor != nil
        holdingOption = keyboard
        initialDirection = direction
        invokingPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let point = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        display = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?
            .visibleFrame ?? .zero
        mouseAtPresentation = NSEvent.mouseLocation
        isOpen = true
        isLoading = true
        updateWindows()
        present()
        Task { [weak self] in
            guard let self else { return }
            await catalog.refresh()
            guard isOpen, sessionID == token else { return }
            isLoading = false
            updateWindows()
            present()
            if pendingCommit {
                commit()
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isOpen else { return }
                let token = sessionID
                await catalog.refresh()
                guard isOpen, sessionID == token else { return }
                updateWindows()
            }
        }
        if dockMode {
            startLeaveTimer()
        }
    }

    private func updateWindows() {
        var candidates = catalog.windows.filter { window in
            (pidFilter == nil || window.pid == pidFilter)
                && (preferences.includeMinimized || (!window.isMinimized && !window.isHidden))
                && (!preferences.currentDisplayOnly || appKitFrame(window.frame).intersects(display))
        }
        let currentID = candidates.first { $0.pid == invokingPID }?.id
        if windows.isEmpty, initialDirection != 0, let currentID,
           let index = candidates.firstIndex(where: { $0.id == currentID }) {
            candidates.insert(candidates.remove(at: index), at: 0)
        }
        // Keep order stable within a session as focus notifications and thumbnails arrive.
        var remaining = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let retained = windows.compactMap { remaining.removeValue(forKey: $0.id) }
        windows = retained + candidates.compactMap { remaining.removeValue(forKey: $0.id) }
        selection.replace(windows.map(\.id))
        if initialDirection != 0, !windows.isEmpty {
            // If the invoking app has no listed window, forward starts at the
            // most recently used candidate instead of skipping it.
            let delta = currentID == nil && initialDirection > 0 ? initialDirection - 1 : initialDirection
            selection.move(delta)
            initialDirection = 0
        }
        selectedID = selection.selected
        refreshThumbnails()
        if panel?.isVisible == true {
            panel?.setFrame(presentationFrame(), display: true)
            panel?.invalidateShadow()
        }
    }

    func move(_ delta: Int) {
        selection.move(delta)
        selectedID = selection.selected
        scheduleThumbnailRefresh()
    }

    func select(_ id: UUID) {
        guard selectedID != id else { return }
        let cursor = NSEvent.mouseLocation
        guard dockMode || hypot(cursor.x - mouseAtPresentation.x, cursor.y - mouseAtPresentation.y) > 3
        else { return }
        selection.replace(windows.map(\.id), preferred: id)
        selectedID = selection.selected
    }

    func commit(_ id: UUID? = nil) {
        guard let target = id ?? selectedID else {
            if isLoading {
                pendingCommit = true
            } else {
                dismiss()
            }
            return
        }
        dismiss()
        Task { await catalog.focus(target) }
    }

    func perform(_ action: ButtonAction) {
        guard let id = selectedID else { return }
        let token = sessionID
        Task {
            await catalog.perform(action, on: id)
            guard isOpen, sessionID == token else { return }
            updateWindows()
            if windows.isEmpty {
                dismiss()
            }
        }
    }

    func dismiss() {
        sessionID = UUID()
        isOpen = false
        holdingOption = false
        pendingCommit = false
        dockDelay?.cancel()
        refreshTimer?.invalidate()
        leaveTimer?.invalidate()
        outsideSince = nil
        panel?.orderOut(nil)
        thumbnails.stop()
        thumbnailRefreshTask?.cancel()
        visibleIDs = []
        windows = []
        selection = WindowBrowserSelection()
        selectedID = nil
    }

    private func releaseOption() {
        if isOpen, holdingOption {
            commit()
        }
    }

    private func refreshThumbnails() {
        let visible = windows.filter { visibleIDs.contains($0.id) || $0.id == selectedID }
        thumbnails.refresh(visible.isEmpty ? Array(windows.prefix(12)) : visible,
                           enabled: preferences.thumbnailsEnabled, selected: selectedID)
    }

    private func appKitFrame(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY,
               width: frame.width, height: frame.height)
    }
}

extension WindowBrowserController {
    private func presentationFrame() -> CGRect {
        let size = usesThumbnails
            ? WindowBrowserGeometry.previewLayout(windowCount: windows.count, scale: preferences.previewScale,
                                                  screenSize: display.size).size
            : CGSize(width: 460 * previewScale,
                     height: (CGFloat(max(1, windows.count)) * 58 + 80) * previewScale)
        return WindowBrowserGeometry.panelFrame(size: size, anchor: anchor, screen: display)
    }

    private func present() {
        presentation.show(controller: self, thumbnails: thumbnails, frame: presentationFrame(),
                          scale: previewScale, dockMode: dockMode)
    }

    private func updateCornerRadius() {
        presentation.updateCornerRadius(scale: previewScale)
    }

    private func scheduleDock(_ target: DockHoverTarget) {
        guard preferences.dockEnabled, !paused, !holdingOption else { return }
        if isOpen, dockMode, pidFilter == target.pid {
            return
        }
        dockDelay?.cancel()
        let delay = preferences.dockAppearanceMilliseconds
        dockDelay = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, target.frame.contains(NSEvent.mouseLocation),
                  NSEvent.pressedMouseButtons == 0 else { return }
            begin(pid: target.pid, anchor: target.frame, keyboard: false, direction: 0)
        }
    }

    private func startLeaveTimer() {
        outsideSince = nil
        leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkMouseExit() }
        }
    }

    private func checkMouseExit() {
        guard isOpen, let panel, let anchor else { return }
        let cursor = NSEvent.mouseLocation
        if panel.frame.insetBy(dx: -6, dy: -6).contains(cursor)
            || anchor.insetBy(dx: -6, dy: -6).contains(cursor) {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) >= preferences.dockDismissalMilliseconds / 1000 {
                dismiss()
            }
        } else {
            outsideSince = Date()
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isOpen else { return event }
        if event.type == .flagsChanged {
            if !event.modifierFlags.contains(.option) {
                releaseOption()
            }
            return event
        }
        guard panel?.isKeyWindow == true else { return event }
        return handleNavigation(event)
    }

    private func handleNavigation(_ event: NSEvent) -> NSEvent? {
        let rowStep = usesThumbnails ? layout.columns : 1
        let direction: [UInt16: Int] = [123: -1, 124: 1, 125: rowStep, 126: -rowStep]
        if let delta = direction[event.keyCode] {
            move(delta); return nil
        }
        switch event.keyCode {
        case 53: dismiss()
        case 36, 76: commit()
        case 48: move(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 13 where event.modifierFlags.contains(.command): perform(.closeWindow)
        case 46 where event.modifierFlags.contains(.command): perform(.minimize)
        default: return event
        }
        return nil
    }
}
