import AppKit
@testable import BlinkerApp
import BlinkerCore
import XCTest

final class WindowBrowserFadeTests: XCTestCase {
    func testRefreshDoesNotRestartAppearanceAndRepeatedHideKeepsOneCompletion() throws {
        var state = WindowBrowserFadeState()
        let appearing = try XCTUnwrap(state.show())
        XCTAssertTrue(state.isPresented)
        XCTAssertNil(state.show())
        XCTAssertEqual(state.transition, appearing)
        XCTAssertTrue(state.complete(appearing))
        XCTAssertNil(state.show())

        let hiding = try XCTUnwrap(state.hide())
        XCTAssertFalse(state.isPresented)
        XCTAssertNil(state.hide())
        XCTAssertEqual(state.transition, hiding)
        XCTAssertFalse(state.complete(appearing))
        XCTAssertTrue(state.complete(hiding))
        XCTAssertNil(state.transition)
        XCTAssertNil(state.hide())
    }

    func testRapidReopenRejectsBothOldAnimationCompletions() throws {
        var state = WindowBrowserFadeState()
        let firstShow = try XCTUnwrap(state.show())
        let oldHide = try XCTUnwrap(state.hide())
        let currentShow = try XCTUnwrap(state.show())

        XCTAssertFalse(state.complete(firstShow))
        XCTAssertFalse(state.complete(oldHide), "An old fade must not order out or clear the new browser")
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.transition, currentShow)
        XCTAssertTrue(state.complete(currentShow))
        XCTAssertTrue(state.isPresented)
    }

    func testOldShowCannotCompleteANewerDismissal() throws {
        var state = WindowBrowserFadeState()
        let appearing = try XCTUnwrap(state.show())
        let hiding = try XCTUnwrap(state.hide())
        XCTAssertFalse(state.complete(appearing))
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.transition, hiding)
        XCTAssertTrue(state.complete(hiding))
    }

    @MainActor
    func testReduceMotionShowsAndHidesSynchronouslyWithoutOrderingDepartureIn() {
        _ = NSApplication.shared
        let window = RecordingWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                                     styleMask: .borderless, backing: .buffered, defer: true)
        let fade = WindowBrowserFade(reduceMotion: { true })
        var appearanceCalls = 0
        var completed = false
        fade.show(window) { appearanceCalls += 1 }
        XCTAssertEqual(appearanceCalls, 1)
        XCTAssertEqual(window.alphaValue, 1)
        fade.show(window) { appearanceCalls += 1 }
        XCTAssertEqual(appearanceCalls, 1, "A catalog refresh must not repeat appearance")

        fade.hide(window) { completed = true }
        XCTAssertTrue(completed)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertEqual(window.frontCount, 0)
        XCTAssertEqual(window.outCount, 1)
    }

    @MainActor
    func testExternallyHiddenWindowRetiresStateWithoutReappearingAndCanReopen() {
        _ = NSApplication.shared
        let window = RecordingWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                                     styleMask: .borderless, backing: .buffered, defer: true)
        var reduced = true
        let fade = WindowBrowserFade(reduceMotion: { reduced })
        var appearanceCalls = 0
        var completed = false
        fade.show(window) { appearanceCalls += 1 }
        window.orderOut(nil) // An application hide happened before the controller dismissed.
        reduced = false
        fade.hide(window, animated: false) { completed = true }
        XCTAssertTrue(completed)
        XCTAssertEqual(window.frontCount, 0)
        XCTAssertEqual(window.alphaValue, 0)
        reduced = true
        fade.show(window) { appearanceCalls += 1 }
        XCTAssertEqual(appearanceCalls, 2)
        XCTAssertEqual(window.alphaValue, 1)
    }

    @MainActor
    func testDeparturePanelCannotTakeKeyboardFocusOrReceiveMouseEvents() {
        _ = NSApplication.shared
        let panel = OverlayPanel(appKitFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
                                 ignoresMouseEvents: true)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

    @MainActor
    private final class RecordingWindow: NSWindow {
        var frontCount = 0
        var outCount = 0

        override func orderFrontRegardless() {
            frontCount += 1
        }

        override func orderOut(_: Any?) {
            outCount += 1
        }
    }
}
