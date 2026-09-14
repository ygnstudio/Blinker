@testable import BlinkerCore
import CoreGraphics
import XCTest

final class TitlebarSamplerTests: XCTestCase {
    // MARK: - Helpers

    /// One RGBA pixel value, each channel 0–255.
    private struct SamplePixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        static let background = SamplePixel(red: 200, green: 120, blue: 80, alpha: 255)
        static let dark = SamplePixel(red: 10, green: 10, blue: 10, alpha: 255)
        static let gray = SamplePixel(red: 200, green: 200, blue: 200, alpha: 255)
        static let transparent = SamplePixel(red: 0, green: 0, blue: 0, alpha: 0)
    }

    /// Builds an RGBA8 CGImage; `pixelAt` returns a color per column.
    private func makeImage(
        width: Int,
        height: Int,
        pixelAt: (Int) -> SamplePixel
    ) -> CGImage {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0 ..< height {
            for columnIndex in 0 ..< width {
                let pixel = pixelAt(columnIndex)
                pixels.append(contentsOf: [pixel.red, pixel.green, pixel.blue, pixel.alpha])
            }
        }
        return pixels.withUnsafeBytes { rawBuffer -> CGImage in
            let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: rawBuffer.baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context!.makeImage()!
        }
    }

    // MARK: - Uniform background

    func testUniformBackgroundSpansFullWidth() {
        let image = makeImage(width: 60, height: 8) { _ in .background }
        let analysis = TitlebarPixelScan.analyze(image)

        XCTAssertNotNil(analysis)
        let run = analysis?.cleanestRun(minimumWidth: 2, preferHigh: false)
        XCTAssertEqual(run, 0 ..< 60)
        XCTAssertEqual(
            analysis?.referenceColor,
            TitlebarPixelScan.RGBColor(red: 200, green: 120, blue: 80)
        )
    }

    // MARK: - Dirty columns

    func testTextBlockIsExcludedFromCleanRun() throws {
        // Uniform bar with a dark "text" block covering columns 20..<30.
        let image = makeImage(width: 60, height: 8) { column in
            (20 ..< 30).contains(column) ? .dark : .background
        }
        let analysis = TitlebarPixelScan.analyze(image)
        let run = try XCTUnwrap(analysis?.cleanestRun(minimumWidth: 5, preferHigh: false))

        XCTAssertFalse((20 ..< 30).overlaps(run))
    }

    func testTransparentColumnsAreExcludedFromCleanRun() {
        // Rounded-corner simulation: the first five columns are transparent.
        let image = makeImage(width: 40, height: 8) { column in
            column < 5 ? .transparent : SamplePixel(red: 180, green: 180, blue: 180, alpha: 255)
        }
        let analysis = TitlebarPixelScan.analyze(image)
        let run = analysis?.cleanestRun(minimumWidth: 2, preferHigh: false)

        XCTAssertEqual(run?.lowerBound, 5)
    }

    // MARK: - Run selection

    func testTieBreaksTowardMaskSide() {
        // Two equal clean runs separated by a dirty middle block.
        let image = makeImage(width: 40, height: 8) { column in
            (15 ..< 25).contains(column) ? .dark : .gray
        }
        let analysis = TitlebarPixelScan.analyze(image)

        let lowRun = analysis?.cleanestRun(minimumWidth: 10, preferHigh: false)
        XCTAssertEqual(lowRun, 0 ..< 15)
        let highRun = analysis?.cleanestRun(minimumWidth: 10, preferHigh: true)
        XCTAssertEqual(highRun, 25 ..< 40)
    }

    func testNoRunWhenEverythingIsDirty() {
        // Alternating solid black/white columns: every column is internally
        // uniform but the column means sit far from the bar-wide reference
        // (mid-gray), so no column can be clean.
        let image = makeImage(width: 40, height: 8) { column in
            column.isMultiple(of: 2) ? .dark : SamplePixel(red: 255, green: 255, blue: 255, alpha: 255)
        }
        let analysis = TitlebarPixelScan.analyze(image)

        XCTAssertEqual(analysis?.cleanestRun(minimumWidth: 4, preferHigh: false), nil)
    }

    func testFullyTransparentCaptureYieldsNoAnalysis() {
        // A span entirely outside the window shape: nothing usable.
        let image = makeImage(width: 20, height: 8) { _ in .transparent }

        XCTAssertNil(TitlebarPixelScan.analyze(image))
    }

    // MARK: - Span selection

    func testSpanFramesCoverSpaceBesideMask() {
        let windowBounds = CGRect(x: 100, y: 200, width: 800, height: 600)
        let maskFrame = CGRect(x: 130, y: 210, width: 60, height: 24)

        let spans = TitlebarSampler.spanFrames(windowBounds: windowBounds, maskFrame: maskFrame)

        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(spans[0].maskIsOnRight)
        XCTAssertEqual(spans[0].rect.minX, 4, accuracy: 0.5)
        XCTAssertEqual(spans[1].rect.maxX, windowBounds.width - 4, accuracy: 0.5)
    }

    func testSpanFramesEmptyWhenMaskFillsWindow() {
        let windowBounds = CGRect(x: 0, y: 0, width: 100, height: 500)
        let maskFrame = CGRect(x: 2, y: 4, width: 96, height: 24)

        let spans = TitlebarSampler.spanFrames(windowBounds: windowBounds, maskFrame: maskFrame)

        XCTAssertTrue(spans.isEmpty)
    }
}

/// Repeat hovers must reuse the sampled backdrop so the mask pill shows
/// its final look without the async capture's grey-glass interim.
final class TitlebarSamplerCacheTests: XCTestCase {
    private let windowBounds = CGRect(x: 100, y: 200, width: 800, height: 600)
    private let maskFrame = CGRect(x: 130, y: 210, width: 60, height: 24)
    private let scale: CGFloat = 2
    private let appearance = "NSAppearanceNameDarkAqua"

    private func seedCache(windowID: CGWindowID = 42) -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        TitlebarSampler.storeCachedMaskImage(
            image: image,
            windowID: windowID,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        )
        return image
    }

    override func tearDown() {
        // The cache is process-global; a fresh entry per test keeps runs
        // independent (windowID 42 + variants are unique per test anyway,
        // but expire the seeded entry explicitly via a far-future lookup).
        _ = TitlebarSampler.cachedMaskImage(
            windowID: 42,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance,
            now: Date.distantFuture
        )
        super.tearDown()
    }

    func testCachedBackdropIsReturnedForSameWindowGeometryAndAppearance() {
        let seeded = seedCache()
        let cached = TitlebarSampler.cachedMaskImage(
            windowID: 42,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        )
        XCTAssertTrue(cached === seeded)
    }

    func testAppearanceChangeInvalidatesCache() {
        seedCache()
        XCTAssertNil(TitlebarSampler.cachedMaskImage(
            windowID: 42,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: "NSAppearanceNameAqua"
        ))
    }

    func testGeometryChangeInvalidatesCache() {
        seedCache()
        let movedFrame = maskFrame.offsetBy(dx: 10, dy: 0)
        XCTAssertNil(TitlebarSampler.cachedMaskImage(
            windowID: 42,
            windowBounds: windowBounds,
            maskFrame: movedFrame,
            scale: scale,
            appearance: appearance
        ))
    }

    func testDifferentWindowMissesCache() {
        seedCache()
        XCTAssertNil(TitlebarSampler.cachedMaskImage(
            windowID: 43,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        ))
    }

    func testEntryExpiresAfterTTL() {
        seedCache()
        let later = Date().addingTimeInterval(61)
        XCTAssertNil(TitlebarSampler.cachedMaskImage(
            windowID: 42,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance,
            now: later
        ))
        // After expiry the entry is evicted, not resurrected.
        XCTAssertNil(TitlebarSampler.cachedMaskImage(
            windowID: 42,
            windowBounds: windowBounds,
            maskFrame: maskFrame,
            scale: scale,
            appearance: appearance
        ))
    }
}

extension TitlebarSamplerCacheTests {
    /// Electron hosts report AX frames with sub-point jitter; the cache key
    /// must collapse it so repeat hovers still hit the cache.
    func testSubPointJitterStillHitsCache() {
        let seeded = seedCache(windowID: 77)
        let jitteredFrame = maskFrame.offsetBy(dx: 0.3, dy: -0.2)
            .insetBy(dx: -0.1, dy: 0.15)
        let jitteredBounds = windowBounds.offsetBy(dx: -0.25, dy: 0.2)
        let cached = TitlebarSampler.cachedMaskImage(
            windowID: 77,
            windowBounds: jitteredBounds,
            maskFrame: jitteredFrame,
            scale: scale,
            appearance: appearance
        )
        XCTAssertTrue(cached === seeded)
    }
}
