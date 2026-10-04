import AppKit
import BlinkerCore
import Combine

/// One app-level owner keeps optional Dock clicks, desktop actions and global pause in sync.
@MainActor
final class DesktopActionsCoordinator: ObservableObject {
    let desktop = DesktopVisibilityController()
    let dock = DockClickController()
    @Published private(set) var isPaused = false
    var onWillToggle: (() -> Void)?
    private let preferences: AppPreferences
    private let permissions: PermissionController
    private var subscriptions = Set<AnyCancellable>()
    private var running = false

    init(preferences: AppPreferences, permissions: PermissionController) {
        self.preferences = preferences
        self.permissions = permissions
    }

    func start() {
        guard !running else { return }
        running = true
        dock.onWillToggle = { [weak self] in self?.onWillToggle?() }
        Publishers.CombineLatest3(preferences.$isDockClickMinimizeEnabled,
                                  permissions.$accessibilityGranted, $isPaused)
            .map { enabled, granted, paused in enabled && granted && !paused }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, running else { return }
                dock.configure(isEnabled: enabled)
            }.store(in: &subscriptions)
        desktop.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        dock.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        desktop.$lastFailureCount.removeDuplicates().dropFirst().sink { count in
            if count > 0 {
                ActionFeedbackController.shared.show(String(localized: "有 \(count) 个窗口未能完成操作。"))
            }
        }.store(in: &subscriptions)
    }

    func toggleDesktop() {
        guard running, !isPaused, !desktop.isBusy else { return }
        guard AccessibilityPermission.isTrusted else {
            permissions.refresh()
            ActionFeedback.report(.permissionRequired)
            return
        }
        onWillToggle?()
        desktop.toggle()
    }

    func setPaused(_ value: Bool) {
        guard isPaused != value else { return }
        isPaused = value
        desktop.setPaused(value)
    }

    func retryDock() {
        permissions.refresh()
        dock.configure(isEnabled: preferences.isDockClickMinimizeEnabled
            && permissions.accessibilityGranted && !isPaused)
    }

    func stop() {
        running = false
        subscriptions.removeAll()
        dock.stop()
        desktop.stop()
    }
}
