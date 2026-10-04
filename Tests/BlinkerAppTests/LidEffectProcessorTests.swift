@testable import BlinkerApp
import CoreImage
import Metal
import XCTest

final class LidEffectProcessorTests: XCTestCase {
    private let extent = CGRect(x: 20, y: 30, width: 160, height: 120)

    func testZeroAndInvalidProgressPreserveTheOriginalImage() {
        let input = CIImage(color: .white).cropped(to: extent)
        for progress in [0.0, -1, .nan, .infinity] {
            XCTAssertTrue(LidEffectProcessor.image(input: input, progress: progress,
                                                   configuration: .init()) === input)
        }
    }

    func testProjectionKeepsTheHingeAndNarrowsContinuouslyWithinBounds() {
        XCTAssertEqual(LidEffectProcessor.topWidth(progress: 0, tilt: 80), 1)
        XCTAssertEqual(LidEffectProcessor.topWidth(progress: 1, tilt: 0), 1)
        var previous = 1.0
        for step in 0 ... 100 {
            let width = LidEffectProcessor.topWidth(progress: Double(step) / 100, tilt: 80)
            XCTAssertGreaterThanOrEqual(width, 0.08)
            XCTAssertLessThanOrEqual(width, previous)
            previous = width
        }
    }

    func testDuoPreservesTranslatedExtentAndClampsProgress() throws {
        let context = try context()
        let input = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8)).cropped(to: extent)
        let full = LidEffectProcessor.image(input: input, progress: 1, configuration: .init())
        let oversized = LidEffectProcessor.image(input: input, progress: 10, configuration: .init())
        XCTAssertEqual(full.extent, extent)
        XCTAssertEqual(oversized.extent, extent)
        XCTAssertEqual(pixel(full, at: CGPoint(x: 90, y: 85), context: context),
                       pixel(oversized, at: CGPoint(x: 90, y: 85), context: context))
    }

    func testMetalMappingPreservesTopBottomOrientationAndNonzeroOrigin() throws {
        let context = try context()
        let bottom = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 20, y: 30, width: 160, height: 60))
        let top = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 20, y: 90, width: 160, height: 60))
        let input = top.composited(over: bottom).cropped(to: extent)
        let bounds = CGRect(x: 4, y: 8, width: 80, height: 60)
        let output = LidEffectProcessor.metalImage(input, bounds: bounds)
        XCTAssertEqual(output.extent, bounds)
        XCTAssertEqual(pixel(output, at: CGPoint(x: 44, y: 18), context: context), [255, 0, 0, 255])
        XCTAssertEqual(pixel(output, at: CGPoint(x: 44, y: 58), context: context), [0, 0, 255, 255])
    }

    func testDuoProjectionKeepsBottomAndMasksOutsideTopCorners() throws {
        let context = try context()
        var configuration = LidEffectConfiguration()
        configuration.frost = 0
        configuration.darkness = 0
        let input = CIImage(color: .white).cropped(to: extent)
        let output = LidEffectProcessor.image(input: input, progress: 1, configuration: configuration)
        XCTAssertGreaterThan(pixel(output, at: CGPoint(x: 100, y: 31), context: context)[0], 240)
        XCTAssertLessThan(pixel(output, at: CGPoint(x: 21, y: 149), context: context)[0], 10)
    }

    private func context() throws -> CIContext {
        try CIContext(mtlDevice: XCTUnwrap(MTLCreateSystemDefaultDevice()))
    }

    private func pixel(_ image: CIImage, at point: CGPoint, context: CIContext) -> [UInt8] {
        render(image, bounds: CGRect(origin: point, size: CGSize(width: 1, height: 1)), context: context)
    }

    private func render(_ image: CIImage, bounds: CGRect, context: CIContext) -> [UInt8] {
        let rowBytes = Int(bounds.width) * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * Int(bounds.height))
        bytes.withUnsafeMutableBytes { storage in
            context.render(image, toBitmap: storage.baseAddress!, rowBytes: rowBytes, bounds: bounds,
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return bytes
    }
}
