import CoreGraphics
import Foundation

/// Pixel-level column analysis for a captured title-bar strip.
///
/// Decodes a CGImage into RGBA8 and derives per-column statistics used by
/// `TitlebarSampler` to locate a clean backdrop run: text, toolbar buttons,
/// and separators show up as high-deviation columns far from the reference
/// color and are skipped.
enum TitlebarPixelScan {
    /// An RGB triple in the 0–255 domain.
    struct RGBColor: Equatable {
        var red = 0.0
        var green = 0.0
        var blue = 0.0

        /// Chebyshev channel distance, in the 0–255 domain.
        func distance(to other: RGBColor) -> Double {
            max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
        }
    }

    /// Per-column statistics of one captured span.
    struct ColumnAnalysis {
        let pixelHeight: Int
        let means: [RGBColor]
        let deviations: [Double]
        let referenceColor: RGBColor

        func isCleanColumn(_ index: Int) -> Bool {
            let uniformColumn = deviations[index] <= cleanThreshold
            let onBackground = means[index].distance(to: referenceColor) <= cleanThreshold
            return uniformColumn && onBackground
        }

        /// The widest contiguous run of clean columns; ties break toward the
        /// mask (`preferHigh` favors the high-x end). Returns `nil` when no
        /// run reaches `minimumWidth` columns.
        func cleanestRun(minimumWidth: Int, preferHigh: Bool) -> Range<Int>? {
            var best: Range<Int>?
            var bestWidth = -1
            var bestProximity = Int.max
            var start: Int?

            func consider(_ run: Range<Int>) {
                guard run.count >= minimumWidth else { return }
                let proximity = preferHigh ? means.count - run.upperBound : run.lowerBound
                let isWider = run.count > bestWidth
                let isCloser = run.count == bestWidth && proximity < bestProximity
                guard isWider || isCloser else { return }
                best = run
                bestWidth = run.count
                bestProximity = proximity
            }

            for index in means.indices {
                if isCleanColumn(index) {
                    if start == nil {
                        start = index
                    }
                } else if let runStart = start {
                    consider(runStart ..< index)
                    start = nil
                }
            }
            if let runStart = start {
                consider(runStart ..< means.count)
            }
            return best
        }
    }

    /// Maximum color distance (0–255) between a pixel and its column mean,
    /// and between a column mean and the reference color, for the column to
    /// count as clean.
    private static let cleanThreshold: Double = 12

    /// Decodes `image` into RGBA8 pixels and derives per-column statistics.
    /// Returns `nil` when the capture has no usable (opaque) columns at all,
    /// e.g. a span entirely outside the window shape.
    static func analyze(_ image: CGImage) -> ColumnAnalysis? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let pixels = pixelBuffer(from: image) else { return nil }
        let means = columnMeans(in: pixels, width: width, height: height)
        let deviations = columnDeviations(in: pixels, width: width, height: height, means: means)
        guard let reference = referenceColor(means: means, deviations: deviations) else { return nil }
        return ColumnAnalysis(
            pixelHeight: height,
            means: means,
            deviations: deviations,
            referenceColor: reference
        )
    }

    private static func pixelBuffer(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }
        return pixels
    }

    private static func columnMeans(
        in pixels: [UInt8],
        width: Int,
        height: Int
    ) -> [RGBColor] {
        var sums = [Double](repeating: 0, count: width * 3)
        for pixelRow in 0 ..< height {
            let rowOffset = pixelRow * width * 4
            for columnIndex in 0 ..< width {
                let offset = rowOffset + columnIndex * 4
                sums[columnIndex * 3] += Double(pixels[offset])
                sums[columnIndex * 3 + 1] += Double(pixels[offset + 1])
                sums[columnIndex * 3 + 2] += Double(pixels[offset + 2])
            }
        }
        let rowTotal = Double(height)
        return (0 ..< width).map { columnIndex in
            RGBColor(
                red: sums[columnIndex * 3] / rowTotal,
                green: sums[columnIndex * 3 + 1] / rowTotal,
                blue: sums[columnIndex * 3 + 2] / rowTotal
            )
        }
    }

    private static func columnDeviations(
        in pixels: [UInt8],
        width: Int,
        height: Int,
        means: [RGBColor]
    ) -> [Double] {
        var deviations = [Double](repeating: 0, count: width)
        var alphaSums = [Double](repeating: 0, count: width)
        for pixelRow in 0 ..< height {
            let rowOffset = pixelRow * width * 4
            for columnIndex in 0 ..< width {
                let offset = rowOffset + columnIndex * 4
                let pixel = RGBColor(
                    red: Double(pixels[offset]),
                    green: Double(pixels[offset + 1]),
                    blue: Double(pixels[offset + 2])
                )
                let distance = pixel.distance(to: means[columnIndex])
                if distance > deviations[columnIndex] {
                    deviations[columnIndex] = distance
                }
                alphaSums[columnIndex] += Double(pixels[offset + 3])
            }
        }
        // Columns mostly outside the window shape (rounded corners, border)
        // can never be backdrop; mark them dirty outright.
        let rowTotal = Double(height)
        let opaqueThreshold = 200.0
        for columnIndex in 0 ..< width where alphaSums[columnIndex] / rowTotal < opaqueThreshold {
            deviations[columnIndex] = Double.greatestFiniteMagnitude
        }
        return deviations
    }

    /// Mean color of the cleanest quarter of the opaque columns — robust
    /// against a minority of text/button pixels skewing a plain average, and
    /// immune to transparent pixels (premultiplied RGB would read as black).
    /// Returns `nil` when no column is opaque.
    private static func referenceColor(
        means: [RGBColor],
        deviations: [Double]
    ) -> RGBColor? {
        let opaqueIndices = means.indices.filter { deviations[$0] < .greatestFiniteMagnitude }
        guard !opaqueIndices.isEmpty else { return nil }
        let order = opaqueIndices.sorted { deviations[$0] < deviations[$1] }
        let sampleCount = max(order.count / 4, 1)
        var total = RGBColor()
        for index in order.prefix(sampleCount) {
            total.red += means[index].red
            total.green += means[index].green
            total.blue += means[index].blue
        }
        let count = Double(sampleCount)
        return RGBColor(red: total.red / count, green: total.green / count, blue: total.blue / count)
    }
}
