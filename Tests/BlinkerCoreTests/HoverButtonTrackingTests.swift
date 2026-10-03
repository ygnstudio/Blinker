import AppKit
@testable import BlinkerCore
import XCTest

@MainActor
final class HoverButtonTrackingTests: XCTestCase {
    private final class FixturePanel: NSPanel {
        /// The long-press gate sees the local test pointer; no desktop cursor
        /// movement or system event injection is needed.
        var pointer = NSPoint(x: 40, y: 40)
    }

    private func track(
        hold: TimeInterval = 0.65,
        hasLongPress: Bool = true,
        mutations: [(TimeInterval, (NSButton, NSView) -> Void)] = []
    ) throws -> (Int, Int) {
        let (panel, content) = makePanel()
        var shortPresses = 0
        var longPresses = 0
        let button = HoverOverlayButtonView(
            frame: NSRect(x: 20, y: 20, width: 40, height: 40),
            symbol: "xmark",
            label: "Test",
            color: .systemRed,
            hasLongPressAction: { hasLongPress },
            onActivate: { _ in shortPresses += 1 },
            onLongPress: { longPresses += 1 },
            pointerLocationInWindow: { _ in panel.pointer }
        )
        button.requiresDwell = { _ in false }
        button.setDwellProgress(1)
        let surface = HoverControlAppearance.makeSurface(for: button)
        surface.frame.origin = NSPoint(x: 20, y: 20)
        content.addSubview(surface)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        guard panel.windowNumber > 0
        else { throw XCTSkip("Native tracking needs a WindowServer-backed test panel") }
        var observedMutations = 0
        var timers = mutations.map { delay, mutation in
            Timer(timeInterval: delay, repeats: false) { _ in
                MainActor.assumeIsolated {
                    observedMutations += 1
                    mutation(button, content)
                }
            }
        }
        timers.append(Timer(timeInterval: hold, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSApp.postEvent(
                    Self.event(.leftMouseUp, location: panel.pointer, in: panel),
                    // Keep release behind drags already posted, even when both timers are overdue.
                    atStart: false
                )
            }
        })
        for timer in timers {
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
        }
        defer { timers.forEach { $0.invalidate() } }
        NSApp.sendEvent(Self.event(.leftMouseDown, location: panel.pointer, in: panel))
        XCTAssertEqual(observedMutations, mutations.count, "every cancellation/recovery step must execute")
        return (shortPresses, longPresses)
    }

    private func makePanel() -> (FixturePanel, NSView) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let panel = FixturePanel(
            contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        panel.contentView = content
        return (panel, content)
    }

    private static func event(_ type: NSEvent.EventType, location: NSPoint,
                              in panel: FixturePanel) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    func testNormalHoldFiresOnlyLongPress() throws {
        let result = try track()
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 1)
    }

    func testDisablingDuringHoldCancelsLongPress() throws {
        let result = try track(mutations: [(0.1, { button, _ in button.isEnabled = false })])
        XCTAssertEqual(result.1, 0)
    }

    func testHidingDuringHoldCancelsLongPress() throws {
        let result = try track(mutations: [(0.1, { button, _ in button.isHidden = true })])
        XCTAssertEqual(result.1, 0)
    }

    func testHidingAncestorDuringHoldCancelsLongPress() throws {
        let result = try track(mutations: [(0.1, { _, content in content.isHidden = true })])
        XCTAssertEqual(result.1, 0)
    }

    private func drag(_ button: NSButton, to point: NSPoint) {
        guard let panel = button.window as? FixturePanel else { return }
        panel.pointer = point
        NSApp.postEvent(Self.event(.leftMouseDragged, location: point, in: panel), atStart: false)
    }

    private func batchDragOutAndBack(_ button: NSButton, stall: TimeInterval = 0) {
        guard let panel = button.window as? FixturePanel else { return }
        for point in [NSPoint(x: 90, y: 90), NSPoint(x: 40, y: 40)] {
            NSApp.postEvent(Self.event(.leftMouseDragged, location: point, in: panel), atStart: false)
        }
        if stall > 0 {
            // Deliberately delay the tracking loop past release's deadline:
            // queued pointer movement still has to precede the release event.
            Thread.sleep(forTimeInterval: stall)
        }
    }

    func testShortPressStillFiresNormally() throws {
        let result = try track(hold: 0.1)
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 0)
    }

    func testUnconfiguredLongHoldStillFiresShortAction() throws {
        let result = try track(hasLongPress: false)
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 0)
    }

    func testDragOutReleaseCancelsBothActions() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in self.drag(button, to: NSPoint(x: 90, y: 90)) }),
        ])
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 0)
    }

    func testDragOutAndBackCancelsOldHoldButKeepsNativeShortClick() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in self.drag(button, to: NSPoint(x: 90, y: 90)) }),
            (0.2, { button, _ in self.drag(button, to: NSPoint(x: 40, y: 40)) }),
        ])
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 0)
    }

    func testDraggingInsideKeepsTheLongPress() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in self.drag(button, to: NSPoint(x: 45, y: 45)) }),
            (0.2, { button, _ in self.drag(button, to: NSPoint(x: 35, y: 35)) }),
        ])
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 1)
    }

    func testBatchedDragOutAndBackCancelsOldHold() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in self.batchDragOutAndBack(button) }),
        ])
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 0)
    }

    func testDelayedTrackingLoopPreservesBatchedDragOrderBeforeRelease() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in self.batchDragOutAndBack(button, stall: 0.8) }),
        ])
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 0)
    }

    func testReenablingDoesNotReviveTheOldPress() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in button.isEnabled = false }),
            (0.2, { button, _ in button.isEnabled = true }),
        ])
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 0)
    }

    func testUnhidingAncestorDoesNotReviveTheOldPress() throws {
        let result = try track(mutations: [
            (0.1, { _, content in content.isHidden = true }),
            (0.2, { _, content in content.isHidden = false }),
        ])
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 0)
    }

    func testDwellResetCancelsAnUnprotectedLongPress() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in (button as? HoverOverlayButtonView)?.resetDwell() }),
        ])
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 0)
    }

    func testRemovingAndReattachingDoesNotReviveTheOldPress() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in button.removeFromSuperview() }),
            (0.2, { button, content in content.addSubview(button) }),
        ])
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 0)
    }

    func testHiddenPanelDoesNotRunEitherAction() throws {
        let result = try track(mutations: [
            (0.1, { button, _ in button.window?.orderOut(nil) }),
        ])
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, 0)
    }
}
