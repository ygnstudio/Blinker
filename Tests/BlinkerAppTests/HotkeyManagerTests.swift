import AppKit
import ApplicationServices
@testable import BlinkerApp
@testable import BlinkerCore
import Carbon.HIToolbox
import XCTest

@MainActor
final class HotkeyManagerTests: XCTestCase {
    private let desktop = HotkeyManager.BindingTarget.desktopToggle
    private let defaultDesktop = HotkeyCombo(keyCode: 2, modifiers: UInt32(controlKey | optionKey))
    private let custom = HotkeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | shiftKey))

    func testDefaultDesktopUsesControlOptionDAndAnIndependentIdentity() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            XCTAssertEqual(manager.desktopToggleCombo, defaultDesktop)
            XCTAssertEqual(manager.desktopToggleCombo?.displayLabel, "⌃⌥D")
            XCTAssertEqual(fixture.driver.installed[desktop.registrationKey], GlobalHotkeyBinding(
                key: desktop.registrationKey, id: desktop.hotKeyID,
                keyCode: 2, modifiers: UInt32(controlKey | optionKey)
            ))
            XCTAssertFalse(HotkeyManager.bindableActions.contains { $0.rawValue == desktop.registrationKey })
            let targets = HotkeyManager.bindableActions.map(HotkeyManager.BindingTarget.windowAction)
                + [.hoverToggle, .desktopToggle]
            XCTAssertEqual(Set(targets.map(\.hotKeyID)).count, targets.count)
        }
    }

    func testUpgradeAddsDesktopDefaultWithoutEnablingOrReplacingExistingBindings() throws {
        try withFixture { fixture in
            fixture.defaults.set(false, forKey: "com.ygnstudio.blinker.hotkeysEnabled")
            try fixture.defaults.set(JSONEncoder().encode([ButtonAction.tileLeft.rawValue: custom]),
                                     forKey: "com.ygnstudio.blinker.hotkeys")
            let manager = fixture.makeManager()
            XCTAssertEqual(manager.desktopToggleCombo, defaultDesktop)
            XCTAssertFalse(manager.isEnabled)
            XCTAssertEqual(manager.bindings, [ButtonAction.tileLeft.rawValue: custom])
            XCTAssertTrue(fixture.driver.installed.isEmpty)
        }
    }

    func testCommandBindingsPersistCustomValuesAndExplicitClearsAcrossRelaunches() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            manager.bindDesktopToggle(custom)
            manager.bindHoverToggle(custom)
            XCTAssertEqual(fixture.makeManager().desktopToggleCombo, custom)
            XCTAssertEqual(fixture.makeManager().hoverToggleCombo, custom)

            manager.clearDesktopToggleBinding()
            manager.clearHoverToggleBinding()
            let reloaded = fixture.makeManager()
            XCTAssertNil(reloaded.desktopToggleCombo)
            XCTAssertNil(reloaded.hoverToggleCombo)
            XCTAssertEqual(reloaded.bindings, manager.bindings)
        }
    }

    func testMalformedDesktopPreferenceFallsBackWithoutLosingOtherSettings() throws {
        try withFixture { fixture in
            fixture.defaults.set(true, forKey: "com.ygnstudio.blinker.hotkeysEnabled")
            fixture.defaults.set(Data("not JSON".utf8), forKey: "com.ygnstudio.blinker.desktop-toggle-hotkey")
            fixture.defaults.set("keep", forKey: "unrelated")
            let manager = fixture.makeManager()
            XCTAssertEqual(manager.desktopToggleCombo, defaultDesktop)
            XCTAssertEqual(fixture.defaults.string(forKey: "unrelated"), "keep")
        }
    }

    func testDesktopDispatchIsSeparateAndBlockedWhileDisabledOrSessionPaused() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            var desktopPresses = 0
            var hoverPresses = 0
            manager.onToggleDesktop = { desktopPresses += 1 }
            manager.onToggleHoverOverlay = { hoverPresses += 1 }
            fixture.driver.fire?(desktop.hotKeyID)
            XCTAssertEqual(desktopPresses, 1)
            XCTAssertEqual(hoverPresses, 0)

            let oldCallback = fixture.driver.fire
            manager.setEnabled(false)
            oldCallback?(desktop.hotKeyID)
            fixture.registry?.onPress?(desktop.hotKeyID)
            XCTAssertEqual(desktopPresses, 1)
            XCTAssertTrue(fixture.driver.installed.isEmpty)

            manager.setEnabled(true)
            manager.setSessionPaused(true)
            oldCallback?(desktop.hotKeyID)
            fixture.registry?.onPress?(desktop.hotKeyID)
            XCTAssertEqual(desktopPresses, 1)
            XCTAssertTrue(fixture.driver.installed.isEmpty)
            manager.setSessionPaused(false)
            fixture.driver.fire?(desktop.hotKeyID)
            XCTAssertEqual(desktopPresses, 2)
        }
    }

    func testDesktopRegistrationFailureAndRetryDoNotDisturbOtherBindings() throws {
        try withFixture { fixture in
            fixture.driver.errors[desktop.registrationKey] = Int32(eventHotKeyExistsErr)
            let manager = fixture.makeManager()
            var presses = 0
            manager.onToggleDesktop = { presses += 1 }
            XCTAssertNotNil(manager.registrationWarning(for: desktop))
            XCTAssertEqual(manager.registrationFailures[desktop.registrationKey],
                           .registration(Int32(eventHotKeyExistsErr)))
            fixture.driver.fire?(desktop.hotKeyID)
            XCTAssertEqual(presses, 0)
            let priorAttempts = fixture.driver.attempts
            fixture.driver.errors = [:]
            manager.retryRegistration(for: desktop)
            XCTAssertNil(manager.registrationWarning(for: desktop))
            XCTAssertEqual(fixture.driver.attempts.count, priorAttempts.count + 1)
            XCTAssertEqual(fixture.driver.attempts.last?.key, desktop.registrationKey)
            fixture.driver.fire?(desktop.hotKeyID)
            XCTAssertEqual(presses, 1)
            manager.clearDesktopToggleBinding()
            fixture.driver.fire?(desktop.hotKeyID)
            XCTAssertEqual(presses, 1)
        }
    }

    func testConflictWarningsExcludeOnlyTheirOwnSlot() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            XCTAssertNil(manager.internalConflictWarning(for: defaultDesktop, target: desktop))
            XCTAssertNotNil(manager.internalConflictWarning(for: defaultDesktop, target: .hoverToggle))
            XCTAssertNotNil(manager.internalConflictWarning(
                for: defaultDesktop,
                target: .windowAction(.tileLeft)
            ))
            manager.bindHoverToggle(custom)
            XCTAssertNotNil(manager.internalConflictWarning(for: custom, target: desktop))
            manager.clearHoverToggleBinding()
            manager.bind(custom, for: .tileRight)
            XCTAssertNotNil(manager.internalConflictWarning(for: custom, target: desktop))
            manager.clearBinding(for: .tileRight)
            manager.bindDesktopToggle(custom)
            XCTAssertNil(manager.internalConflictWarning(for: custom, target: desktop))
        }
    }

    func testRecordingReleasesRegistrationsAndEscapeRestoresThemWithoutDispatch() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            defer { manager.endRecording() }
            var presses = 0
            manager.onToggleDesktop = { presses += 1 }
            let oldCallback = fixture.driver.fire
            manager.beginRecordingDesktopToggle()
            XCTAssertEqual(manager.recordingTarget, desktop)
            XCTAssertTrue(fixture.driver.installed.isEmpty)
            oldCallback?(desktop.hotKeyID)
            fixture.registry?.onPress?(desktop.hotKeyID)
            XCTAssertEqual(presses, 0)
            XCTAssertTrue(try manager.handleRecordingKeyEvent(keyEvent(kVK_Escape)))
            XCTAssertNil(manager.recordingTarget)
            XCTAssertNotNil(fixture.driver.installed[desktop.registrationKey])
            XCTAssertEqual(manager.desktopToggleCombo, defaultDesktop)
        }
    }

    func testDesktopRecorderHandlesBareKeysTabAndAValidCombination() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            defer { manager.endRecording() }
            manager.beginRecordingDesktopToggle()
            XCTAssertTrue(try manager.handleRecordingKeyEvent(keyEvent(kVK_ANSI_A)))
            XCTAssertNotNil(manager.recordingHint)
            XCTAssertEqual(manager.recordingTarget, desktop)
            XCTAssertFalse(try manager.handleRecordingKeyEvent(keyEvent(kVK_Tab)))
            XCTAssertTrue(try manager.handleRecordingKeyEvent(keyEvent(
                kVK_ANSI_B,
                modifiers: [.control, .shift]
            )))
            XCTAssertEqual(manager.desktopToggleCombo, custom)
            XCTAssertNil(manager.recordingTarget)
            XCTAssertNil(manager.recordingHint)
            XCTAssertEqual(fixture.driver.installed[desktop.registrationKey]?.keyCode, UInt32(kVK_ANSI_B))
        }
    }

    func testDisabledRecordingIsBlockedButPausedEditingDoesNotRegisterOrDispatch() throws {
        try withFixture { fixture in
            let manager = fixture.makeManager()
            defer { manager.endRecording() }
            var presses = 0
            manager.onToggleDesktop = { presses += 1 }
            manager.beginRecordingDesktopToggle()
            manager.setEnabled(false)
            XCTAssertNil(manager.recordingTarget)
            manager.beginRecordingDesktopToggle()
            XCTAssertNil(manager.recordingTarget)
            XCTAssertTrue(fixture.driver.installed.isEmpty)

            manager.setEnabled(true)
            manager.beginRecordingDesktopToggle()
            manager.setSessionPaused(true)
            XCTAssertNil(manager.recordingTarget)
            manager.beginRecordingDesktopToggle()
            XCTAssertEqual(manager.recordingTarget, desktop)
            XCTAssertTrue(fixture.driver.installed.isEmpty)
            XCTAssertTrue(try manager.handleRecordingKeyEvent(keyEvent(
                kVK_ANSI_B,
                modifiers: [.control, .shift]
            )))
            XCTAssertEqual(manager.desktopToggleCombo, custom)
            XCTAssertNil(manager.recordingTarget)
            XCTAssertTrue(fixture.driver.installed.isEmpty)
            fixture.registry?.onPress?(desktop.hotKeyID)
            XCTAssertEqual(presses, 0)
            manager.setSessionPaused(false)
            XCTAssertEqual(fixture.driver.installed[desktop.registrationKey]?.keyCode, custom.keyCode)
            manager.beginRecordingDesktopToggle()
            manager.beginRecordingDesktopToggle()
            XCTAssertNil(manager.recordingTarget)
            XCTAssertNotNil(fixture.driver.installed[desktop.registrationKey])
        }
    }

    private func keyEvent(_ keyCode: Int, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                       timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                       charactersIgnoringModifiers: "", isARepeat: false,
                                       keyCode: UInt16(keyCode)))
    }

    private func withFixture(_ body: (HotkeyFixture) throws -> Void) throws {
        let domain = "Blinker.HotkeyManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        try body(HotkeyFixture(defaults: defaults))
    }
}

private final class HotkeyFixture {
    let defaults: UserDefaults
    let driver = AppTestHotkeyDriver()
    private(set) var registry: GlobalHotkeyRegistry?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func makeManager() -> HotkeyManager {
        let registry = GlobalHotkeyRegistry(driver: driver)
        self.registry = registry
        return HotkeyManager(frontWindowPerformer: FrontWindowActionPerformer(performer: NoWindowActions()),
                             defaults: defaults, registry: registry)
    }
}

private final class NoWindowActions: WindowActionPerforming {
    func perform(_: ButtonAction, window _: AXUIElement, processIdentifier _: pid_t) {
        XCTFail("Desktop shortcuts must not perform individual window actions")
    }

    func pressNativeButton(subrole _: String, window _: AXUIElement, processIdentifier _: pid_t) {
        XCTFail("No native window action is expected")
    }
}

private final class AppTestHotkeyDriver: HotkeyRegistrationDriving {
    var errors: [String: Int32] = [:]
    var attempts: [GlobalHotkeyBinding] = []
    var installed: [String: GlobalHotkeyBinding] = [:]
    var fire: ((UInt32) -> Void)?

    func installHandler(onPress: @escaping (UInt32) -> Void) -> Int32 {
        fire = onPress
        return 0
    }

    func removeHandler() {
        fire = nil
    }

    func register(_ binding: GlobalHotkeyBinding) -> Int32 {
        attempts.append(binding)
        let status = errors[binding.key] ?? 0
        if status == 0 {
            installed[binding.key] = binding
        }
        return status
    }

    func unregister(_ key: String) {
        installed[key] = nil
    }
}
