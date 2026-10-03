import AppKit
import Combine

/// Session-scoped work, bounded memory, no background video streams or disk screenshots.
@MainActor
public final class WindowThumbnailStore: ObservableObject {
    @Published public private(set) var images: [UUID: NSImage] = [:]
    @Published public private(set) var permissionGranted: Bool
    @Published public private(set) var captureUnavailable = false
    @Published public private(set) var isRetrying = false
    public var canCapture: ((UUID) async -> Bool)?
    private let cache = NSCache<NSString, NSImage>()
    private let source: any WindowThumbnailCapturing
    private let permissionCheck: () -> Bool
    private var offscreenAttempts: [UUID: Date] = [:]
    private var session: UUID?
    private var requestedWindows: [BrowserWindow] = []
    private(set) var captureTask: Task<Void, Never>?
    private var pending: (token: UUID, windows: [BrowserWindow])?

    public convenience init() {
        self.init(source: ScreenCaptureThumbnailSource(), permissionCheck: CGPreflightScreenCaptureAccess)
    }

    init(source: any WindowThumbnailCapturing, permissionCheck: @escaping () -> Bool) {
        self.source = source
        self.permissionCheck = permissionCheck
        permissionGranted = permissionCheck()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 64
    }

    public func checkPermission() {
        permissionGranted = permissionCheck()
        if !permissionGranted {
            clear()
        }
    }

    /// Called only by the explicit settings button, never during a hover or key press.
    public func requestPermission() {
        CGRequestScreenCaptureAccess()
        checkPermission()
    }

    /// The browser can retain its last pixels during a brief, noninteractive
    /// exit. Work is invalidated immediately in both modes.
    public func stop(preservingPresentation: Bool = false) {
        session = nil
        pending = nil
        requestedWindows = []
        if !preservingPresentation {
            captureUnavailable = false
            isRetrying = false
            images = [:]
        }
    }

    /// Retry only the current, already bounded request; this never asks for permission.
    public func retry() {
        guard captureUnavailable, !isRetrying, !requestedWindows.isEmpty else { return }
        checkPermission()
        guard permissionGranted else { return }
        isRetrying = true
        enqueueCapture(requestedWindows)
    }

    /// Explicitly disabling thumbnails or losing permission also discards the
    /// session cache; ordinary panel dismissal keeps it for minimized windows.
    public func clear() {
        stop()
        cache.removeAllObjects()
        offscreenAttempts = [:]
    }

    public func refresh(_ windows: [BrowserWindow], enabled: Bool, selected: UUID?) {
        offscreenAttempts = offscreenAttempts.filter { Date().timeIntervalSince($0.value) < 15 }
        checkPermission()
        guard enabled, permissionGranted else {
            clear()
            return
        }
        // Bound strong image references as well as NSCache. Selection is first;
        // lazy-grid visibility drives which other windows need work.
        var seen = Set<UUID>()
        let unique = windows.filter { seen.insert($0.id).inserted }
        let prioritized = unique.filter { $0.id == selected } + unique.filter { $0.id != selected }
        let ordered = Array(prioritized.prefix(32))
        // Visibility and catalog refreshes may repeat while capture is suspended.
        // Focus order alone must not invalidate the image that is already being produced.
        if session != nil, captureTask != nil, Self.equivalent(ordered, requestedWindows) {
            return
        }
        requestedWindows = ordered
        images = Dictionary(uniqueKeysWithValues: ordered.compactMap { window in
            guard let image = cache.object(forKey: window.id.uuidString as NSString) else { return nil }
            return (window.id, image)
        })
        // Background tabs and already cached minimized windows need no new surface.
        guard ordered.contains(where: needsCapture) else {
            session = nil
            pending = nil
            captureUnavailable = false
            isRetrying = false
            return
        }
        // A failed capture service gets an explicit retry, not a silent retry every two seconds.
        guard !captureUnavailable || isRetrying else { return }
        enqueueCapture(ordered)
    }

    private func enqueueCapture(_ windows: [BrowserWindow]) {
        let token = UUID()
        session = token
        pending = (token, windows)
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            guard let self else { return }
            // One capture batch in flight. New visible items replace pending work rather
            // than launching more non-cancellable ScreenCaptureKit requests.
            while let batch = pending {
                pending = nil
                await capture(batch.windows, token: batch.token)
            }
            captureTask = nil
        }
    }

    private func capture(_ windows: [BrowserWindow], token: UUID) async {
        guard !windows.isEmpty, session == token else { return }
        let prepared = await source.prepare()
        guard session == token else { return }
        captureUnavailable = !prepared
        isRetrying = false
        guard prepared else { return }
        for window in windows {
            guard session == token else { return }
            await capture(window, token: token)
        }
    }

    private func capture(_ window: BrowserWindow, token: UUID) async {
        // An inactive tab shares the selected tab's window surface. Never
        // label that surface as the inactive tab; retain its own cache only.
        guard needsCapture(window) else { return }
        guard await canCapture?(window.id) != false, session == token else { return }
        let offscreen = window.isMinimized || window.isHidden
        if !offscreen {
            offscreenAttempts.removeValue(forKey: window.id)
        }
        let captured = await source.capture(window)
        guard session == token else { return }
        guard await canCapture?(window.id) != false, session == token else { return }
        guard let captured else {
            if offscreen {
                offscreenAttempts[window.id] = Date()
            }
            return
        }
        offscreenAttempts.removeValue(forKey: window.id)
        cache.setObject(captured.image, forKey: window.id.uuidString as NSString, cost: captured.cost)
        images[window.id] = captured.image
    }

    private func needsCapture(_ window: BrowserWindow) -> Bool {
        guard !window.isTab || window.isSelectedTab else { return false }
        guard window.isMinimized || window.isHidden else { return true }
        // Keep a good image, and back off only after a real failed offscreen capture.
        guard images[window.id] == nil else { return false }
        return offscreenAttempts[window.id].map { Date().timeIntervalSince($0) >= 15 } ?? true
    }

    private static func equivalent(_ left: [BrowserWindow], _ right: [BrowserWindow]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { first, second in
            first.id == second.id && first.pid == second.pid && first.frame == second.frame
                && (first.captureTitle ?? first.title) == (second.captureTitle ?? second.title)
                && first.isMinimized == second.isMinimized && first.isHidden == second.isHidden
                && first.isTab == second.isTab && first.isSelectedTab == second.isSelectedTab
        }
    }
}
