import AppKit
import ScreenCaptureKit

struct CapturedWindowThumbnail {
    let image: NSImage
    let cost: Int
}

@MainActor
protocol WindowThumbnailCapturing {
    func prepare() async -> Bool
    func capture(_ window: BrowserWindow) async -> CapturedWindowThumbnail?
}

/// Owns the ScreenCaptureKit details; session lifetime and caching stay in the store.
@MainActor
final class ScreenCaptureThumbnailSource: WindowThumbnailCapturing {
    private var content: SCShareableContent?

    func prepare() async -> Bool {
        content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        return content != nil
    }

    func capture(_ window: BrowserWindow) async -> CapturedWindowThumbnail? {
        guard let content, let source = captureSource(for: window, in: content.windows),
              source.frame.width.isFinite, source.frame.height.isFinite,
              source.frame.width > 0, source.frame.height > 0 else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: source)
        let config = SCStreamConfiguration()
        let scale = min(640 / source.frame.width, 400 / source.frame.height, 1)
        config.width = max(1, Int(source.frame.width * scale))
        config.height = max(1, Int(source.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        ) else { return nil }
        return CapturedWindowThumbnail(image: NSImage(cgImage: image, size: .zero),
                                       cost: image.bytesPerRow * image.height)
    }

    private func captureSource(for window: BrowserWindow, in sources: [SCWindow]) -> SCWindow? {
        let owned = sources.filter { $0.owningApplication?.processID == window.pid && $0.windowLayer == 0 }
        let surfaces: [[String: Any]] = owned.map {
            [kCGWindowOwnerPID as String: window.pid, kCGWindowLayer as String: 0,
             kCGWindowNumber as String: $0.windowID, kCGWindowName as String: $0.title ?? "",
             kCGWindowBounds as String: $0.frame.dictionaryRepresentation]
        }
        guard let id = Self.captureID(for: window, in: surfaces) else { return nil }
        return owned.first { $0.windowID == id }
    }

    nonisolated static func captureID(for window: BrowserWindow, in surfaces: [[String: Any]]) -> UInt32? {
        // The earlier CG ID is a derived hint, not AX identity. Revalidate against
        // the current capture snapshot rather than trusting a stale or ambiguous ID.
        let match = WindowDiscovery.captureMatch(surfaces, pid: window.pid, frame: window.frame,
                                                 title: window.captureTitle ?? window.title,
                                                 allowOffscreenTitleMatch: window.isMinimized || window
                                                     .isHidden)
        return match?[kCGWindowNumber as String] as? UInt32
    }
}
