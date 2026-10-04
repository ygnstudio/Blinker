import AppKit
@testable import BlinkerApp
import XCTest

@MainActor
final class MenuBarChargingAnimationTests: XCTestCase {
    private var charging: MenuBarSystemSnapshot {
        .init(battery: .init(percentage: 65, isCharging: true, isConnectedToPower: true, isLowPower: false),
              network: .wifi(strength: 3), volume: .init(scalar: 0.5, isMuted: false))
    }

    func testPolicyRequiresChargingKnownBatteryAndTheEffectSwitch() {
        var snapshot = charging
        var configuration = MenuBarConfiguration()
        XCTAssertTrue(allowed(snapshot, configuration: configuration))
        configuration.showsChargingHeartbeat = false
        XCTAssertTrue(
            allowed(snapshot, configuration: configuration),
            "The arc can animate without heartbeat"
        )
        configuration.showsChargingEffect = false
        configuration.showsChargingHeartbeat = true
        XCTAssertFalse(
            allowed(snapshot, configuration: configuration),
            "Heartbeat cannot bypass the effect switch"
        )
        configuration.showsChargingEffect = true
        snapshot.battery?.percentage = nil
        XCTAssertFalse(allowed(snapshot, configuration: configuration))
        snapshot = charging
        snapshot.battery?.isCharging = false
        XCTAssertFalse(allowed(snapshot, configuration: configuration))
        XCTAssertFalse(allowed(.unknown, configuration: configuration))
    }

    func testPolicyStopsForSuspensionReducedMotionAndEitherLowPowerReading() {
        let configuration = MenuBarConfiguration()
        XCTAssertFalse(MenuBarChargingAnimation.isAllowed(snapshot: charging, configuration: configuration,
                                                          suspended: true, reducedMotion: false,
                                                          lowPower: false))
        XCTAssertFalse(MenuBarChargingAnimation.isAllowed(snapshot: charging, configuration: configuration,
                                                          suspended: false, reducedMotion: true,
                                                          lowPower: false))
        XCTAssertFalse(MenuBarChargingAnimation.isAllowed(snapshot: charging, configuration: configuration,
                                                          suspended: false, reducedMotion: false,
                                                          lowPower: true))
        var snapshot = charging
        snapshot.battery?.isLowPower = true
        XCTAssertFalse(allowed(snapshot, configuration: configuration))
    }

    func testActualLayersHonorHeartbeatIndicatorAndEffectSwitchWithoutDuplicates() throws {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
        let animation = MenuBarChargingAnimation(reducedMotion: { false }, lowPower: { false })
        var configuration = MenuBarConfiguration()
        animation.update(
            host: view,
            snapshot: charging,
            configuration: configuration,
            size: 72,
            suspended: false
        )
        let initial = try XCTUnwrap(container(in: view))
        XCTAssertEqual(initial.sublayers?.compactMap(\.name), ["charge", "heartbeat"])
        XCTAssertNotNil(initial.sublayers?.first?.animation(forKey: "charge"))
        XCTAssertNotNil(initial.sublayers?.last?.animation(forKey: "heartbeat"))
        animation.update(
            host: view,
            snapshot: charging,
            configuration: configuration,
            size: 72,
            suspended: false
        )
        XCTAssertIdentical(container(in: view), initial, "Layout must not restart a running animation")
        configuration.showsChargingIndicator = false
        animation.update(
            host: view,
            snapshot: charging,
            configuration: configuration,
            size: 72,
            suspended: false
        )
        XCTAssertEqual(container(in: view)?.sublayers?.compactMap(\.name), ["charge"])
        XCTAssertNil(initial.superlayer)
        XCTAssertTrue(initial.sublayers?.allSatisfy { ($0.animationKeys() ?? []).isEmpty } == true)
        configuration.showsChargingEffect = false
        animation.update(
            host: view,
            snapshot: charging,
            configuration: configuration,
            size: 72,
            suspended: false
        )
        XCTAssertNil(container(in: view))
    }

    func testDisablingColorsKeepsHeartbeatMonochromeInBothAppearances() throws {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
        let animation = MenuBarChargingAnimation(reducedMotion: { false }, lowPower: { false })
        defer { animation.stop() }
        var configuration = MenuBarConfiguration()
        configuration.usesBatteryColors = false
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: name)
            animation.update(host: view, snapshot: charging, configuration: configuration,
                             size: 72, suspended: false)
            let bolt = try XCTUnwrap(container(in: view)?.sublayers?.last as? CAShapeLayer)
            let color = try XCTUnwrap(bolt.fillColor
                .flatMap { NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB) })
            XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.01)
            XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.01)
            XCTAssertEqual(color.brightnessComponent > 0.5, name == .darkAqua)
        }
    }

    func testChangingEnvironmentCancelsLayersAndAllowsCleanRestart() {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        var reduced = false
        var lowPower = false
        let animation = MenuBarChargingAnimation(reducedMotion: { reduced }, lowPower: { lowPower })
        let configuration = MenuBarConfiguration()
        func update() {
            animation.update(host: view, snapshot: charging, configuration: configuration,
                             size: 22, suspended: false)
        }
        update()
        XCTAssertNotNil(container(in: view))
        reduced = true
        update()
        XCTAssertNil(container(in: view))
        reduced = false
        lowPower = true
        update()
        XCTAssertNil(container(in: view))
        lowPower = false
        update()
        XCTAssertNotNil(container(in: view))
        animation.stop()
        animation.stop()
        XCTAssertNil(container(in: view))
    }

    private func allowed(_ snapshot: MenuBarSystemSnapshot, configuration: MenuBarConfiguration) -> Bool {
        MenuBarChargingAnimation.isAllowed(snapshot: snapshot, configuration: configuration,
                                           suspended: false, reducedMotion: false, lowPower: false)
    }

    private func container(in view: NSView) -> CALayer? {
        view.layer?.sublayers?.first { $0.name == "blinkerChargingEffects" }
    }
}
