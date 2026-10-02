import AppKit
import Combine

/// Shared by keyboard switching, Dock previews and the traffic-light HUD.
@MainActor
public final class WindowCatalog: ObservableObject {
    @Published public private(set) var windows: [BrowserWindow] = []
    @Published public private(set) var isLoading = false
    public var includeTabs = true {
        didSet {
            if includeTabs != oldValue {
                stopTracking()
            }
        }
    }

    private let queue = DispatchQueue(label: "com.ygnstudio.blinker.catalog", qos: .userInitiated)
    private let discovery = WindowDiscovery()
    private let focusObserver = ActiveWindowObserver()
    private var focusTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var revision = UUID()

    public init() {
        focusObserver.onChange = { [weak self] in
            guard let self else { return }
            focusTask?.cancel()
            focusTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    public func stopTracking() {
        focusObserver.stop()
        focusTask?.cancel()
        focusTask = nil
        revision = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
    }

    public func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        isLoading = true
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo
                .processIdentifier
                && !SessionPause.shared.contains($0.bundleIdentifier ?? "")
        }
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        focusObserver.observe(focusedPID)
        let includeTabs = includeTabs
        let token = revision
        let task = Task { [weak self, queue, discovery] in
            let result: [BrowserWindow] = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: discovery.discover(apps: apps, focusedPID: focusedPID,
                                                                      includeTabs: includeTabs))
                }
            }
            guard let self, revision == token, !Task.isCancelled else { return }
            windows = result
            refreshTask = nil
            isLoading = false
        }
        refreshTask = task
        await task.value
    }

    public func canCapture(_ id: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [discovery] in continuation.resume(returning: discovery.canCapture(id)) }
        }
    }

    public func focus(_ id: UUID) async {
        let success = await withCheckedContinuation { continuation in
            queue.async { [discovery] in continuation.resume(returning: discovery.focus(id)) }
        }
        if !success {
            ActionFeedback.report(.unsupportedWindow)
        }
    }

    public func perform(_ action: ButtonAction, on id: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [discovery] in
                if let target = discovery.targets[id] {
                    DefaultWindowActionPerformer.shared.perform(
                        action, window: target.element, processIdentifier: target.pid
                    )
                } else {
                    ActionFeedback.report(.unsupportedWindow)
                }
                continuation.resume()
            }
        }
        await refresh()
    }
}
