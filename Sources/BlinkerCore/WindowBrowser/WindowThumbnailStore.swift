import AppKit
import Combine

/// Session-scoped work, bounded memory, no background video streams or disk screenshots.
@MainActor
public final class WindowThumbnailStore: ObservableObject {
    @Published public private(set) var images: [UUID: NSImage] = [:]
    @Published public private(set) var permissionGranted: Bool
    public var canCapture: ((UUID) async -> Bool)?
    private let cache = NSCache<NSString, NSImage>()
    private let source: any WindowThumbnailCapturing
    private let permissionCheck: () -> Bool
    private var offscreenAttempts: [UUID: Date] = [:]
    private var session: UUID?
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

    public func stop() {
        session = nil
        pending = nil
        images = [:]
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
        let token = UUID()
        session = token
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
        images = Dictionary(uniqueKeysWithValues: ordered.compactMap { window in
            guard let image = cache.object(forKey: window.id.uuidString as NSString) else { return nil }
            return (window.id, image)
        })
        pending = (token, ordered)
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
        guard !windows.isEmpty, session == token, await source.prepare(), session == token else { return }
        for window in windows {
            guard session == token else { return }
            // An inactive tab shares the selected tab's window surface. Never
            // label that surface as the inactive tab; retain its own cache only.
            guard !window.isTab || window.isSelectedTab else { continue }
            guard await canCapture?(window.id) != false, session == token else { continue }
            let offscreen = window.isMinimized || window.isHidden
            if offscreen {
                // Keep a good image and avoid repeatedly asking macOS for an
                // unavailable minimized surface on every two-second refresh.
                if images[window.id] != nil {
                    continue
                }
                if let last = offscreenAttempts[window.id], Date().timeIntervalSince(last) < 15 {
                    continue
                }
                offscreenAttempts[window.id] = Date()
            } else {
                offscreenAttempts.removeValue(forKey: window.id)
            }
            guard let captured = await source.capture(window), session == token,
                  await canCapture?(window.id) != false, session == token else { continue }
            cache.setObject(captured.image, forKey: window.id.uuidString as NSString, cost: captured.cost)
            images[window.id] = captured.image
        }
    }
}
