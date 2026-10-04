@testable import BlinkerApp
import XCTest

final class LidEffectPresentationRequestTests: XCTestCase {
    func testQuickOpeningCanRequestAnEndingAtZeroTarget() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 0, openingStartProgress: 0.7))
        XCTAssertTrue(request.isRequested)
        XCTAssertTrue(request.isFinishing)
        XCTAssertFalse(request.hasPresented)
        XCTAssertEqual(request.progress, 0)
        XCTAssertEqual(request.initialProgress, 0.7)
        XCTAssertFalse(request.finish(), "The opening seed already requested its ending")
    }

    func testClosingBeforeCaptureStartsPreservesObservedPeakUntilFirstFrame() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 0.8, openingStartProgress: nil))
        XCTAssertTrue(request.update(progress: 0.3, openingStartProgress: nil))
        XCTAssertTrue(request.finish())
        XCTAssertTrue(request.isRequested)
        XCTAssertTrue(request.isFinishing)
        XCTAssertEqual(request.progress, 0)
        XCTAssertEqual(request.initialProgress, 0.8)

        request.didPresent()
        XCTAssertTrue(request.hasPresented)
        XCTAssertEqual(request.initialProgress, 0)
        XCTAssertTrue(request.isRequested)
        XCTAssertTrue(request.isFinishing)
    }

    func testFinishingPresentedEffectDoesNotReseedAnOldPeak() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 0.9, openingStartProgress: nil))
        request.didPresent()
        XCTAssertTrue(request.update(progress: 0.2, openingStartProgress: nil))
        XCTAssertTrue(request.finish())
        XCTAssertEqual(request.initialProgress, 0,
                       "The renderer must fade from its current strength instead of jumping to the old peak")
        XCTAssertEqual(request.progress, 0)
    }

    func testRepeatedFinishKeepsOnePendingEnding() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 0.6, openingStartProgress: nil))
        XCTAssertTrue(request.finish())
        for _ in 0 ..< 10 {
            XCTAssertFalse(request.finish())
            XCTAssertTrue(request.isRequested)
            XCTAssertTrue(request.isFinishing)
            XCTAssertEqual(request.initialProgress, 0.6)
        }
    }

    func testNewPositiveTargetCancelsFinishingWithoutLosingPresentation() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 0.6, openingStartProgress: nil))
        request.didPresent()
        XCTAssertTrue(request.finish())
        XCTAssertTrue(request.update(progress: 0.4, openingStartProgress: nil))
        XCTAssertTrue(request.isRequested)
        XCTAssertTrue(request.hasPresented)
        XCTAssertFalse(request.isFinishing)
        XCTAssertEqual(request.progress, 0.4)
        XCTAssertEqual(request.initialProgress, 0)
        XCTAssertTrue(request.finish(), "A later ending remains independent from the canceled one")
    }

    func testClearDropsEveryPriorRequestAndItsPeak() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 0.9, openingStartProgress: 0.8))
        request.didPresent()
        XCTAssertTrue(request.finish())
        request.clear()

        XCTAssertFalse(request.isRequested)
        XCTAssertFalse(request.isFinishing)
        XCTAssertFalse(request.hasPresented)
        XCTAssertEqual(request.progress, 0)
        XCTAssertEqual(request.initialProgress, 0)
        XCTAssertFalse(request.finish())

        XCTAssertTrue(request.update(progress: 0.2, openingStartProgress: nil))
        XCTAssertTrue(request.finish())
        XCTAssertEqual(request.initialProgress, 0.2,
                       "A new capture must not inherit the previous request's peak")
    }

    func testInvalidTargetCannotCreatePresentationEvenWithAnOpeningSeed() {
        for target in [-0.1, .nan, .infinity, -.infinity] {
            var request = LidEffectPresentationRequest()
            XCTAssertFalse(request.update(progress: target, openingStartProgress: 0.7))
            XCTAssertFalse(request.isRequested)
            XCTAssertFalse(request.isFinishing)
            XCTAssertEqual(request.progress, 0)
            XCTAssertEqual(request.initialProgress, 0)
        }
    }

    func testZeroTargetWithoutValidOpeningSeedCannotCreatePresentation() {
        let seeds: [Double?] = [nil, 0, -0.1, .nan, .infinity, -.infinity]
        for seed in seeds {
            var request = LidEffectPresentationRequest()
            XCTAssertFalse(request.update(progress: 0, openingStartProgress: seed))
            XCTAssertFalse(request.isRequested)
            XCTAssertFalse(request.finish())
            XCTAssertEqual(request.initialProgress, 0)
        }
    }

    func testFiniteTargetsAndSeedsAreBoundedBeforeRendering() {
        var request = LidEffectPresentationRequest()

        XCTAssertTrue(request.update(progress: 2, openingStartProgress: 3))
        XCTAssertEqual(request.progress, 1)
        XCTAssertEqual(request.initialProgress, 1)
        XCTAssertTrue(request.finish())
        XCTAssertEqual(request.initialProgress, 1)
    }
}
