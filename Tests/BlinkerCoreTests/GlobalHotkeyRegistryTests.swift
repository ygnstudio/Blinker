@testable import BlinkerCore
import XCTest

final class GlobalHotkeyRegistryTests: XCTestCase {
    private let left = GlobalHotkeyBinding(key: "left", id: 1, keyCode: 123, modifiers: 6144)
    private let hover = GlobalHotkeyBinding(key: "hover", id: 2, keyCode: 4, modifiers: 6144)

    func testFailureIsPublishedPerBindingAndRetryPreservesSuccessfulRegistration() {
        let driver = TestHotkeyDriver()
        driver.registrationErrors["left"] = -9878
        let registry = GlobalHotkeyRegistry(driver: driver)
        var fired: [UInt32] = []
        registry.onPress = { fired.append($0) }
        registry.update([left, hover], enabled: true, paused: false)
        XCTAssertEqual(registry.failures, ["left": .registration(-9878)])
        XCTAssertEqual(driver.installed, [hover])
        driver.fire?(left.id)
        driver.fire?(hover.id)
        XCTAssertEqual(fired, [hover.id])

        driver.registrationErrors = [:]
        registry.retry("left")
        XCTAssertTrue(registry.failures.isEmpty)
        XCTAssertEqual(driver.attempts, [left, hover, left])
        XCTAssertEqual(driver.installed, [hover, left])
        driver.fire?(left.id)
        XCTAssertEqual(fired, [hover.id, left.id])
        registry.retry("hover")
        XCTAssertEqual(driver.attempts.count, 3, "retry must not disturb a working shortcut")
    }

    func testHandlerFailureExplainsEveryConfiguredBindingAndRetryRecoversAll() {
        let driver = TestHotkeyDriver()
        driver.handlerError = -50
        let registry = GlobalHotkeyRegistry(driver: driver)
        registry.update([left, hover], enabled: true, paused: false)
        XCTAssertEqual(registry.failures, ["left": .handler(-50), "hover": .handler(-50)])
        XCTAssertTrue(driver.attempts.isEmpty)
        driver.handlerError = 0
        registry.retry("hover")
        XCTAssertEqual(driver.handlerAttempts, 2)
        XCTAssertEqual(driver.installed, [left, hover])
        XCTAssertTrue(registry.failures.isEmpty)
    }

    func testPausingAndDisablingClearFailuresAndPreventRetryOrDispatch() {
        for paused in [false, true] {
            let driver = TestHotkeyDriver()
            driver.registrationErrors["left"] = -9878
            let registry = GlobalHotkeyRegistry(driver: driver)
            registry.update([left, hover], enabled: true, paused: false)
            XCTAssertEqual(registry.failures["left"], .registration(-9878))
            let oldCallback = driver.fire
            var fired = false
            registry.onPress = { _ in fired = true }
            registry.update([left, hover], enabled: paused, paused: paused)
            XCTAssertTrue(registry.failures.isEmpty)
            XCTAssertTrue(driver.installed.isEmpty)
            XCTAssertEqual(driver.handlerRemovals, 1)
            registry.retry("left")
            oldCallback?(hover.id)
            XCTAssertFalse(fired)
            XCTAssertEqual(driver.attempts.count, 2)
            driver.registrationErrors = [:]
            registry.update([left, hover], enabled: true, paused: false)
            XCTAssertEqual(driver.installed, [left, hover])
            XCTAssertTrue(registry.failures.isEmpty)
        }
    }

    func testClearingOrChangingBindingRemovesStaleFailureWithoutLosingOtherBindings() {
        let driver = TestHotkeyDriver()
        driver.registrationErrors["left"] = -9878
        let registry = GlobalHotkeyRegistry(driver: driver)
        registry.update([left, hover], enabled: true, paused: false)
        XCTAssertEqual(registry.failures["left"], .registration(-9878))
        registry.update([hover], enabled: true, paused: false)
        XCTAssertTrue(registry.failures.isEmpty)
        registry.retry("left")
        XCTAssertEqual(driver.attempts, [left, hover])
        driver.registrationErrors = [:]
        let replacement = GlobalHotkeyBinding(key: "left", id: 1, keyCode: 124, modifiers: 6144)
        registry.update([replacement, hover], enabled: true, paused: false)
        XCTAssertEqual(driver.installed, [hover, replacement])
        XCTAssertEqual(driver.handlerAttempts, 1)
        registry.update([], enabled: true, paused: false)
        XCTAssertTrue(driver.installed.isEmpty)
        XCTAssertEqual(driver.handlerRemovals, 1)
    }

    func testReplacingSuccessfulBindingAndDeinitReleaseCarbonResources() {
        let driver = TestHotkeyDriver()
        var registry: GlobalHotkeyRegistry? = GlobalHotkeyRegistry(driver: driver)
        registry?.update([left], enabled: true, paused: false)
        let replacement = GlobalHotkeyBinding(key: "left", id: 1, keyCode: 124, modifiers: 6144)
        registry?.update([replacement], enabled: true, paused: false)
        XCTAssertEqual(driver.installed, [replacement])
        XCTAssertEqual(driver.removed, ["left"])
        registry = nil
        XCTAssertTrue(driver.installed.isEmpty)
        XCTAssertEqual(driver.removed, ["left", "left"])
        XCTAssertEqual(driver.handlerRemovals, 1)
    }
}

private final class TestHotkeyDriver: HotkeyRegistrationDriving {
    var registrationErrors: [String: Int32] = [:]
    var handlerError: Int32 = 0
    var handlerAttempts = 0
    var handlerRemovals = 0
    var attempts: [GlobalHotkeyBinding] = []
    var installed: [GlobalHotkeyBinding] = []
    var removed: [String] = []
    var fire: ((UInt32) -> Void)?

    func installHandler(onPress: @escaping (UInt32) -> Void) -> Int32 {
        handlerAttempts += 1
        if handlerError == 0 {
            fire = onPress
        }
        return handlerError
    }

    func removeHandler() {
        handlerRemovals += 1
        fire = nil
    }

    func register(_ binding: GlobalHotkeyBinding) -> Int32 {
        attempts.append(binding)
        let status = registrationErrors[binding.key] ?? 0
        if status == 0 {
            installed.append(binding)
        }
        return status
    }

    func unregister(_ key: String) {
        removed.append(key)
        installed.removeAll { $0.key == key }
    }
}
