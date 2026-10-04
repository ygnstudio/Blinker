@testable import BlinkerApp
import XCTest

@MainActor
final class ScreenEffectControllerTests: XCTestCase {
    private final class Source: LidAngleReadingSource {
        var reads = 0
        var completion: (@MainActor @Sendable (LidAngleReading) -> Void)?
        func read(completion: @escaping @MainActor @Sendable (LidAngleReading) -> Void) {
            reads += 1
            self.completion = completion
        }

        func stop() {}

        func complete(_ angle: Double) {
            let completion = completion
            self.completion = nil
            completion?(.init(angle: angle, status: .available))
        }
    }

    private final class Overlay: LidEffectPresenting {
        var onFailure: ((String) -> Void)?
        var onFirstFrame: (() -> Void)?
        var onFinished: (() -> Void)?
        var updates = 0
        var clears = 0
        var finishes = 0
        var seeds: [Double] = []
        var lastProgress = 0.0
        func update(progress: Double, configuration _: LidEffectConfiguration,
                    openingStartProgress: Double?) {
            updates += 1
            lastProgress = progress
            if let openingStartProgress {
                seeds.append(openingStartProgress)
            }
        }

        func finish() {
            finishes += 1
        }

        func clear() {
            clears += 1
        }
    }

    private func withPreferences(_ body: (LidEffectPreferences) throws -> Void) throws {
        let suite = "Blinker.ScreenEffectControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(LidEffectPreferences(defaults: defaults))
    }

    func testConstructionAndDefaultStartupDoNotReadSensorOrCapture() throws {
        try withPreferences { preferences in
            let source = Source()
            let overlay = Overlay()
            var checks = 0
            let controller = ScreenEffectController(sensor: LidAngleMonitor(source: source),
                                                    preferences: preferences, overlay: overlay,
                                                    permissionCheck: { checks += 1; return true })
            XCTAssertEqual(checks, 0)
            XCTAssertEqual(source.reads, 0)
            controller.start()
            let firstChecks = checks
            controller.start()
            XCTAssertEqual(checks, firstChecks, "Repeated start must not duplicate subscriptions")
            XCTAssertEqual(source.reads, 0)
            controller.tick(time: 1)
            XCTAssertEqual(overlay.updates, 0)
            XCTAssertEqual(controller.progress, 0)
            controller.stop()
        }
    }

    func testDeniedPermissionPreventsCaptureEvenWithEnabledEffectAndValidAngle() throws {
        try withPreferences { preferences in
            preferences.update { $0.isEnabled = true }
            let source = Source()
            let sensor = LidAngleMonitor(source: source)
            let overlay = Overlay()
            let controller = ScreenEffectController(sensor: sensor, preferences: preferences,
                                                    overlay: overlay, permissionCheck: { false })
            controller.start()
            // Feed only the fake source. Do not override actual lock or Reduce Motion state.
            sensor.start()
            source.complete(110)
            controller.tick(time: 1)
            sensor.refresh()
            source.complete(45)
            controller.tick(time: 2)
            XCTAssertFalse(controller.permissionGranted)
            XCTAssertEqual(controller.progress, 0)
            XCTAssertEqual(overlay.updates, 0)
            XCTAssertFalse(controller.isPresenting)
            controller.stop()
        }
    }

    func testPermissionRevocationClearsPresentationWithoutChangingOptIn() throws {
        try withPreferences { preferences in
            let source = Source()
            let overlay = Overlay()
            var granted = true
            let controller = ScreenEffectController(sensor: LidAngleMonitor(source: source),
                                                    preferences: preferences, overlay: overlay,
                                                    permissionCheck: { granted })
            controller.refreshPermission()
            XCTAssertTrue(controller.permissionGranted)
            let cleared = overlay.clears
            granted = false
            controller.refreshPermission()
            XCTAssertFalse(controller.permissionGranted)
            XCTAssertGreaterThan(overlay.clears, cleared)
            XCTAssertFalse(preferences.configuration.isEnabled)
            XCTAssertEqual(source.reads, 0)
            XCTAssertEqual(overlay.updates, 0)
        }
    }

    func testBackendFailurePausesAndResumeOnlyRechecksPermission() throws {
        try withPreferences { preferences in
            let source = Source()
            let overlay = Overlay()
            let controller = ScreenEffectController(sensor: LidAngleMonitor(source: source),
                                                    preferences: preferences, overlay: overlay,
                                                    permissionCheck: { false })
            controller.start()
            overlay.onFailure?("Test capture failure")
            XCTAssertTrue(controller.isPaused)
            XCTAssertEqual(controller.errorMessage, "Test capture failure")
            XCTAssertEqual(controller.progress, 0)
            XCTAssertFalse(controller.isPresenting)
            controller.resume()
            XCTAssertFalse(controller.isPaused)
            XCTAssertNil(controller.errorMessage)
            XCTAssertFalse(controller.permissionGranted)
            XCTAssertEqual(overlay.updates, 0)
            XCTAssertEqual(source.reads, 0)
            controller.stop()
        }
    }

    func testCalibrationRequiresAnAvailableAngleWithinPhysicalReferenceRange() throws {
        try withPreferences { preferences in
            let source = Source()
            let sensor = LidAngleMonitor(source: source)
            let controller = ScreenEffectController(sensor: sensor, preferences: preferences,
                                                    overlay: Overlay(), permissionCheck: { false })
            controller.calibrate()
            XCTAssertEqual(preferences.configuration.referenceAngle, 110)
            sensor.start()
            source.complete(270)
            controller.calibrate()
            XCTAssertEqual(preferences.configuration.referenceAngle, 110)
            sensor.refresh()
            source.complete(120)
            controller.calibrate()
            XCTAssertEqual(preferences.configuration.referenceAngle, 120)
            sensor.stop()
            controller.calibrate()
            XCTAssertEqual(preferences.configuration.referenceAngle, 120)
            XCTAssertFalse(preferences.configuration.isEnabled)
        }
    }

    func testStopRemovesPreferenceSubscriptionAndDoesNotRestartFromLaterEdits() throws {
        try withPreferences { preferences in
            let source = Source()
            let overlay = Overlay()
            var checks = 0
            let controller = ScreenEffectController(sensor: LidAngleMonitor(source: source),
                                                    preferences: preferences, overlay: overlay,
                                                    permissionCheck: { checks += 1; return false })
            controller.start()
            controller.stop()
            let stoppedChecks = checks
            preferences.update { $0.isEnabled = true }
            controller.tick(time: 10)
            XCTAssertEqual(checks, stoppedChecks)
            XCTAssertEqual(source.reads, 0)
            XCTAssertEqual(overlay.updates, 0)
            XCTAssertEqual(controller.progress, 0)
        }
    }

    private typealias Feed = @MainActor (Double, Double) -> Void

    private func withRunningEffect(_ body: @MainActor (ScreenEffectController, Overlay, Feed) throws
        -> Void) throws {
        try withPreferences { preferences in
            preferences.update {
                $0.isEnabled = true
                $0.referenceAngle = 120
                $0.sensitivity = 3
                $0.clearDelay = 0.2
            }
            let source = Source()
            let sensor = LidAngleMonitor(source: source)
            let overlay = Overlay()
            let controller = ScreenEffectController(sensor: sensor, preferences: preferences,
                                                    overlay: overlay, permissionCheck: { true })
            controller.start()
            defer { controller.stop() }
            try XCTSkipIf(controller.isSuspended || controller.reducesMotion,
                          "Respect the host's lock and Reduce Motion settings")
            let feed: Feed = { angle, time in
                if source.completion == nil {
                    sensor.refresh()
                }
                source.complete(angle)
                controller.tick(time: time)
            }
            try body(controller, overlay, feed)
        }
    }

    func testJitterDoesNotStartCaptureAndConfirmedLidMovementStillWorks() throws {
        try withRunningEffect { controller, overlay, feed in
            feed(100, 0)
            for index in 1 ... 20 {
                feed(index.isMultiple(of: 2) ? 101 : 99, Double(index) * 0.05)
            }
            XCTAssertEqual(
                overlay.updates,
                0,
                "Jitter below the reference must not start the capture backend"
            )
            feed(90, 1.05)
            XCTAssertEqual(overlay.updates, 0, "Wait for confirmation before allocating capture resources")
            controller.tick(time: 1.21)
            controller.tick(time: 1.31)
            XCTAssertEqual(overlay.updates, 0, "Cached readings cannot confirm a single anomalous sample")
            feed(90, 1.36)
            XCTAssertEqual(overlay.updates, 1)
            XCTAssertGreaterThan(controller.progress, 0)
            feed(90, 1.7)
            XCTAssertEqual(controller.progress, 0)
            for index in 0 ... 30 {
                feed(index.isMultiple(of: 2) ? 91 : 89, 1.75 + Double(index) * 0.05)
            }
            XCTAssertEqual(overlay.updates, 1, "Rebound must not reopen a cleared capture session")
            feed(90, 3.3)
            feed(90, 3.65)
            feed(94, 3.7)
            XCTAssertEqual(overlay.updates, 1)
            feed(94, 3.86)
            XCTAssertEqual(overlay.updates, 2, "Deliberate opening also starts an effect after confirmation")
            let openingProgress = controller.progress
            feed(97, 4.2)
            XCTAssertGreaterThan(controller.progress, 0)
            XCTAssertLessThan(
                controller.progress,
                openingProgress,
                "Opening fades the same angle-driven effect"
            )
            feed(120, 4.25)
            XCTAssertEqual(controller.progress, 0)
        }
    }

    func testQuickOpeningSurvivesUntilCaptureCanShowItsFirstFrame() throws {
        try withRunningEffect { controller, overlay, feed in
            let clears = overlay.clears
            for (index, angle) in [80.0, 100, 120, 130, 135, 140].enumerated() {
                feed(angle, Double(index) * 0.05)
            }
            XCTAssertGreaterThan(overlay.updates, 0, "A fast opening must not disappear during confirmation")
            XCTAssertEqual(overlay.seeds.count, 1)
            XCTAssertGreaterThan(try XCTUnwrap(overlay.seeds.first), 0)
            XCTAssertEqual(overlay.lastProgress, 0)
            XCTAssertEqual(
                overlay.clears,
                clears,
                "Zero target must not cancel capture before its first frame"
            )
            overlay.onFirstFrame?()
            XCTAssertTrue(controller.isPresenting)
            overlay.onFinished?()
            XCTAssertFalse(controller.isPresenting)
        }
    }

    func testOrdinaryFinishKeepsPresentationUntilFinalFrameButSafetyClearIsImmediate() throws {
        try withRunningEffect { controller, overlay, feed in
            feed(120, 0)
            feed(90, 0.05)
            feed(89, 0.21)
            XCTAssertGreaterThan(overlay.updates, 0)
            overlay.onFirstFrame?()
            let clears = overlay.clears
            let finishes = overlay.finishes
            feed(89, 0.6)
            XCTAssertGreaterThan(overlay.finishes, finishes)
            XCTAssertEqual(overlay.clears, clears)
            XCTAssertTrue(
                controller.isPresenting,
                "Escape remains available during the visible exit animation"
            )
            feed(.nan, 0.65)
            XCTAssertGreaterThan(overlay.clears, clears)
            XCTAssertFalse(controller.isPresenting, "Invalid hardware evidence must clear immediately")
        }
    }
}
