import AppKit
import CoreGraphics
import os
import ScreenCaptureKit

/// Captures a pixel-accurate backdrop for the mask from the host window's
/// own title bar.
///
/// The native buttons sit inside the mask area, so the strip directly behind
/// the mask cannot be sampled — instead the title-bar space *beside* the
/// button group is captured and analyzed column by column (`TitlebarPixelScan`).
/// A column counts as clean only when every pixel stays close to the column's
/// mean color and the column mean stays close to the bar's reference color,
/// so title text, toolbar buttons, and separators are detected as dirty
/// columns and skipped. The widest clean run is stretched across the mask;
/// when neither side offers a clean run, the bar's reference color is used
/// as a solid backdrop. When nothing can be captured at all, callers fall
/// back to the material backdrop.
///
/// Sampling uses `SCScreenshotManager` one-shot captures (macOS 14+); the
/// legacy `CGWindowListCreateImage` is hard-unavailable in recent SDKs.
public enum TitlebarSampler {
    private static let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "titlebar-sampler")

    /// Minimum width (pt) of a clean run worth using as the backdrop strip.
    private static let minimumStripWidth: CGFloat = 12
    /// Clearance (pt) kept from the window edges and the button group so
    /// window borders, rounded corners, and button shadows never leak into
    /// the sample.
    private static let clearance: CGFloat = 4
    /// Pixels trimmed from each end of a clean run to avoid bleeding edges.
    private static let runInsetPixels = 1

    /// `true` when the user has already granted Screen Recording access.
    public static func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts the system Screen Recording permission dialog. The grant
    /// arrives asynchronously; the overlay keeps falling back to glass
    /// until `hasScreenCapturePermission()` turns `true`.
    public static func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Renders the mask backdrop by sampling `windowID` beside the button
    /// group, stretched to `maskFrame`'s size. Returns `nil` when screen
    /// capture is unavailable (no permission, window gone, no sample) —
    /// callers fall back to the material backdrop.
    ///
    /// Successful results are cached (see `cachedMaskImage`) so repeat hovers
    /// on the same window show the sampled pill immediately, without waiting
    /// for the async capture chain again.
    ///
    /// - Parameter scale: Backing scale factor for the output pixel size;
    ///   read `NSScreen.backingScaleFactor` on the main thread and pass it in.
    /// - Parameter appearance: Name of the current system appearance; a
    ///   light/dark switch invalidates cached backdrops. Read on the main
    ///   thread and pass it in.
    static func maskImage(
        windowID: CGWindowID,
        windowBounds: CGRect,
        maskFrame: CGRect,
        scale: CGFloat,
        appearance: String
    ) async -> NSImage? {
        let cacheKey = BackdropCacheKey(
            windowID: windowID,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        )
        if let cached = cachedBackdrop(for: cacheKey) {
            return cached
        }
        guard hasScreenCapturePermission() else {
            logger.error("sampled mask skipped: Screen Recording permission missing")
            return nil
        }
        let spans = spanFrames(windowBounds: windowBounds, maskFrame: maskFrame)
        guard !spans.isEmpty else {
            logger.info("sampled mask skipped: no capturable span beside the button group")
            return nil
        }

        let shareable = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let scWindow = shareable?.windows.first(where: { $0.windowID == windowID }) else {
            logger.error("sampled mask skipped: window \(windowID) not found in SCShareableContent")
            return nil
        }

        let sample = await sampleBackdrop(spans: spans, scWindow: scWindow, scale: scale)
        if let crop = sample.crop {
            let image = stretchedImage(from: crop, size: maskFrame.size)
            storeCachedBackdrop(image, for: cacheKey)
            return image
        }
        guard let color = sample.referenceColor else {
            logger.error("sampled mask skipped: no span captured (capture error?)")
            return nil
        }
        logger.info("sampled mask: no clean run; falling back to reference color")
        let image = solidImage(color: color, size: maskFrame.size)
        storeCachedBackdrop(image, for: cacheKey)
        return image
    }

    // MARK: - Backdrop cache

    /// How long a sampled backdrop stays valid: repeat hovers within this
    /// window reuse the cached image and show the sampled pill instantly,
    /// without the grey-glass interim of the async capture chain. After it
    /// expires the next hover re-samples and picks up appearance or
    /// title-bar content changes.
    private static let backdropCacheTTL: TimeInterval = 60
    private static let backdropCacheLock = NSLock()
    private static var backdropCache:
        [BackdropCacheKey: (image: NSImage, sampledAt: Date)] = [:]

    /// Identity of a cached backdrop: same window, same geometry (so moving
    /// or resizing the host window misses), same display scale, and same
    /// system appearance. Geometry is quantized to whole points because some
    /// hosts (notably Electron apps) report AX frames with sub-point jitter;
    /// exact-rect keys would miss on every hover and the cache would be
    /// useless there.
    private struct BackdropCacheKey: Hashable {
        let windowID: CGWindowID
        let windowBounds: CGRect
        let maskFrame: CGRect
        let scale: CGFloat
        let appearance: String

        init(
            windowID: CGWindowID,
            windowBounds: CGRect,
            maskFrame: CGRect,
            scale: CGFloat,
            appearance: String
        ) {
            self.windowID = windowID
            self.windowBounds = Self.quantized(windowBounds)
            self.maskFrame = Self.quantized(maskFrame)
            self.scale = scale
            self.appearance = appearance
        }

        /// Rounds a rect's components to whole points, collapsing sub-point
        /// jitter while still distinguishing real geometry changes.
        private static func quantized(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.origin.x.rounded(),
                y: rect.origin.y.rounded(),
                width: rect.size.width.rounded(),
                height: rect.size.height.rounded()
            )
        }
    }

    /// Returns the cached backdrop for this window/geometry/appearance when
    /// a fresh one exists, else `nil`. Call on the main thread while
    /// building the mask panel to skip the async capture entirely.
    static func cachedMaskImage(
        windowID: CGWindowID,
        windowBounds: CGRect,
        maskFrame: CGRect,
        scale: CGFloat,
        appearance: String,
        now: Date = Date()
    ) -> NSImage? {
        let key = BackdropCacheKey(
            windowID: windowID,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        )
        return cachedBackdrop(for: key, now: now)
    }

    /// Stores a backdrop for later cache hits. Internal so tests can seed
    /// the cache; production callers store via `maskImage`.
    static func storeCachedMaskImage(
        image: NSImage,
        windowID: CGWindowID,
        windowBounds: CGRect,
        maskFrame: CGRect,
        scale: CGFloat,
        appearance: String
    ) {
        let key = BackdropCacheKey(
            windowID: windowID,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        )
        storeCachedBackdrop(image, for: key)
    }

    private static func cachedBackdrop(for key: BackdropCacheKey, now: Date = Date()) -> NSImage? {
        backdropCacheLock.withLock {
            guard let entry = backdropCache[key] else { return nil }
            guard now.timeIntervalSince(entry.sampledAt) < backdropCacheTTL else {
                backdropCache.removeValue(forKey: key)
                return nil
            }
            return entry.image
        }
    }

    private static func storeCachedBackdrop(_ image: NSImage, for key: BackdropCacheKey) {
        backdropCacheLock.withLock {
            backdropCache[key] = (image, Date())
        }
    }

    // MARK: - Span selection

    /// A capturable strip of title-bar space beside the button group.
    struct Span {
        /// Window-local rectangle (top-left origin) to capture.
        let rect: CGRect
        /// `true` when the mask sits on the span's right side (left span),
        /// used to break clean-run ties toward the mask.
        let maskIsOnRight: Bool
    }

    /// The capturable strips left and right of the mask, in window-local
    /// coordinates, or an empty array when neither side offers enough room.
    static func spanFrames(windowBounds: CGRect, maskFrame: CGRect) -> [Span] {
        let maskLeft = maskFrame.minX - windowBounds.minX
        let maskRight = maskFrame.maxX - windowBounds.minX
        let maskTop = maskFrame.minY - windowBounds.minY
        let leftWidth = maskLeft - clearance * 2
        let rightWidth = windowBounds.width - clearance * 2 - maskRight

        var spans: [Span] = []
        if leftWidth >= minimumStripWidth {
            spans.append(Span(
                rect: CGRect(
                    x: clearance,
                    y: maskTop,
                    width: leftWidth,
                    height: maskFrame.height
                ),
                maskIsOnRight: true
            ))
        }
        if rightWidth >= minimumStripWidth {
            spans.append(Span(
                rect: CGRect(
                    x: maskRight + clearance,
                    y: maskTop,
                    width: rightWidth,
                    height: maskFrame.height
                ),
                maskIsOnRight: false
            ))
        }
        return spans
    }

    // MARK: - Sampling

    /// Outcome of one sampling pass over every span.
    private struct BackdropSample {
        /// Cleanest crop across all spans, if any clean run was found.
        let crop: CGImage?
        /// Reference color of the first capturable span, used as the solid
        /// fallback when no clean run exists.
        let referenceColor: TitlebarPixelScan.RGBColor?
    }

    private static func sampleBackdrop(
        spans: [Span],
        scWindow: SCWindow,
        scale: CGFloat
    ) async -> BackdropSample {
        var bestCrop: CGImage?
        var bestRunWidth = 0
        var referenceColor: TitlebarPixelScan.RGBColor?
        let minimumPixels = Int((minimumStripWidth * scale).rounded())

        for span in spans {
            guard let captured = await capture(span: span, scWindow: scWindow, scale: scale) else {
                continue
            }
            guard let analysis = TitlebarPixelScan.analyze(captured) else { continue }
            if referenceColor == nil {
                referenceColor = analysis.referenceColor
            }
            guard
                let run = analysis.cleanestRun(
                    minimumWidth: minimumPixels,
                    preferHigh: span.maskIsOnRight
                )
            else { continue }
            guard let crop = croppedImage(from: captured, run: run, height: analysis.pixelHeight) else {
                continue
            }
            if run.count > bestRunWidth {
                bestCrop = crop
                bestRunWidth = run.count
            }
        }
        return BackdropSample(crop: bestCrop, referenceColor: referenceColor)
    }

    private static func capture(
        span: Span,
        scWindow: SCWindow,
        scale: CGFloat
    ) async -> CGImage? {
        var configuration = SCStreamConfiguration()
        // sourceRect is window-local, top-left origin — same axis as the
        // global CG/AX coordinate space, so a plain origin shift applies.
        configuration.sourceRect = span.rect
        configuration.width = Int((span.rect.width * scale).rounded())
        configuration.height = Int((span.rect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            logger.error("span capture failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func croppedImage(
        from image: CGImage,
        run: Range<Int>,
        height: Int
    ) -> CGImage? {
        // Trim only runs comfortably wider than the trims themselves, so the
        // crop can never collapse toward zero width.
        let inset = run.count > runInsetPixels * 4 ? runInsetPixels : 0
        let cropRect = CGRect(
            x: run.lowerBound + inset,
            y: 0,
            width: run.count - inset * 2,
            height: height
        )
        return image.cropping(to: cropRect)
    }

    private static func stretchedImage(from crop: CGImage, size: CGSize) -> NSImage {
        let stretched = NSImage(size: size)
        stretched.lockFocusFlipped(false)
        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        NSImage(cgImage: crop, size: size)
            .draw(in: CGRect(origin: .zero, size: size))
        stretched.unlockFocus()
        return stretched
    }

    private static func solidImage(color: TitlebarPixelScan.RGBColor, size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        NSColor(
            calibratedRed: CGFloat(color.red / 255),
            green: CGFloat(color.green / 255),
            blue: CGFloat(color.blue / 255),
            alpha: 1
        ).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
