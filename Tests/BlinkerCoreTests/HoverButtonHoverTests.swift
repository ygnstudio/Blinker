import AppKit
@testable import BlinkerCore
import XCTest

@MainActor
final class HoverButtonHoverTests: XCTestCase {
    private final class FixturePanel: NSPanel {
        var showsContent = true
        var pointer = NSPoint(x: -100, y: -100)
        override var isVisible: Bool {
            showsContent
        }
    }

    private func button(size: CGFloat = 31) -> NSButton {
        HoverControlAppearance.makePreviewButton(
            frame: CGRect(x: 0, y: 0, width: size, height: size), action: .closeWindow, color: .systemRed
        )
    }

    func testHoverAndPressComposeWithoutChangingFramesOrColor() throws {
        let button = button()
        let surface = HoverControlAppearance.makeSurface(for: button)
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let face = try XCTUnwrap(feedback.subviews.first)
        face.updateLayer()
        let originalColor = face.layer?.backgroundColor
        let frame = button.frame
        withExtendedLifetime(surface) {
            feedback.setHovered(true, reduceMotion: false, animated: false)
            XCTAssertEqual(feedback.layer?.sublayerTransform.m11 ?? 0, 1.1, accuracy: 0.001)
            feedback.setPressed(true, reduceMotion: false, animated: false)
            XCTAssertEqual(feedback.layer?.sublayerTransform.m11 ?? 0, 1.1 * 0.96, accuracy: 0.001)
            feedback.setPressed(false, reduceMotion: false, animated: true)
            XCTAssertEqual(feedback.layer?.sublayerTransform.m11 ?? 0, 1.1, accuracy: 0.001)
            feedback.setHovered(false, reduceMotion: false, animated: true)
            XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
            XCTAssertEqual(button.frame, frame)
            XCTAssertEqual(surface.frame, frame)
            XCTAssertEqual(face.layer?.backgroundColor, originalColor)
            XCTAssertIdentical(button.hitTest(CGPoint(x: 1, y: frame.midY)), button)
            XCTAssertTrue(button.wantsUpdateLayer)
        }
    }

    func testHoverPreservesGlassRimAtSmallAndLargeSizes() throws {
        for size: CGFloat in [12, 28, 31, 48, 96] {
            let button = button(size: size)
            let surface = HoverControlAppearance.makeSurface(for: button)
            let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
            let face = try XCTUnwrap(feedback.subviews.first)
            withExtendedLifetime(surface) {
                feedback.setHovered(true, reduceMotion: false, animated: false)
                let transform = feedback.layer!.sublayerTransform
                XCTAssertGreaterThan(transform.m11, 1)
                XCTAssertLessThanOrEqual(face.bounds.width * transform.m11, size - 1 + 0.001)
                XCTAssertEqual(size / 2 * transform.m11 + transform.m41, size / 2, accuracy: 0.001)
            }
        }
    }

    func testHoverRetargetsOneAnimationAndPressInterruptsIt() throws {
        let button = button()
        let surface = HoverControlAppearance.makeSurface(for: button)
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let layer = try XCTUnwrap(feedback.layer)
        withExtendedLifetime(surface) {
            feedback.setHovered(true, reduceMotion: false, animated: true)
            XCTAssertEqual(layer.animationKeys()?.count, 1)
            let outwardScale = layer.sublayerTransform
            feedback.setHovered(false, reduceMotion: false, animated: true)
            XCTAssertEqual(layer.animationKeys()?.count, 1)
            let animation = layer.animation(forKey: layer.animationKeys()!.first!) as? CABasicAnimation
            XCTAssertEqual((animation?.fromValue as? NSValue)?.caTransform3DValue.m11, outwardScale.m11)
            XCTAssertEqual((animation?.toValue as? NSValue)?.caTransform3DValue.m11, 1)
            feedback.setPressed(true, reduceMotion: false, animated: false)
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
            XCTAssertEqual(layer.sublayerTransform.m11, 0.96, accuracy: 0.001)
        }
    }

    func testReducedMotionKeepsDistinctStaticHoverAndPressSignals() throws {
        let button = button()
        let surface = HoverControlAppearance.makeSurface(for: button)
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let face = try XCTUnwrap(feedback.subviews.first)
        withExtendedLifetime(surface) {
            feedback.setHovered(true, reduceMotion: true, animated: true)
            XCTAssertEqual(face.layer?.borderWidth, 1)
            feedback.setPressed(true, reduceMotion: true, animated: true)
            XCTAssertEqual(face.layer?.borderWidth, 1.5)
            feedback.setPressed(false, reduceMotion: true, animated: true)
            XCTAssertEqual(face.layer?.borderWidth, 1)
            feedback.setHovered(false, reduceMotion: true, animated: true)
            XCTAssertEqual(face.layer?.borderWidth, 0)
            XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
            XCTAssertTrue((feedback.layer?.animationKeys() ?? []).isEmpty)
        }
    }

    private func makeFixture(
        reduceMotion: @escaping () -> Bool = { false }
    ) -> (FixturePanel, HoverOverlayButtonView) {
        _ = NSApplication.shared
        let panel = FixturePanel(
            contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        let button = HoverOverlayButtonView(
            frame: CGRect(x: 0, y: 0, width: 31, height: 31), symbol: "xmark", label: "Test",
            color: .systemRed,
            onActivate: { _ in XCTFail("Hover must never activate a button") },
            pointerLocationInWindow: { [weak panel] _ in panel?.pointer ?? .zero }
        )
        let surface = HoverControlAppearance.makeSurface(for: button, reduceMotion: reduceMotion)
        panel.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        panel.contentView?.addSubview(surface)
        button.updateTrackingAreas()
        return (panel, button)
    }

    private func hoverDiagnostics(_ button: NSButton) -> String {
        let feedback = button.superview as? HoverButtonPressFeedback
        let face = feedback?.subviews.first
        let state: [String] = [
            "systemReduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)",
            "hasWindow=\(button.window != nil)",
            "visible=\(button.window?.isVisible == true)",
            "key=\(button.window?.isKeyWindow == true)",
            "enabled=\(button.isEnabled)",
            "hidden=\(button.isHiddenOrHasHiddenAncestor)",
            "buttonBounds=\(button.bounds)",
            "visibleRect=\(button.visibleRect)",
            "feedbackBounds=\(String(describing: feedback?.bounds))",
            "faceBounds=\(String(describing: face?.bounds))",
            "faceBorder=\(String(describing: face?.layer?.borderWidth))",
        ]
        return state.joined(separator: "; ")
    }

    func testTrackingAreaWorksInInactivePanelAndDetectsInitialPointer() throws {
        let (panel, button) = makeFixture()
        defer { panel.close() }
        XCTAssertFalse(panel.isKeyWindow)
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let area = try XCTUnwrap(button.trackingAreas.first { $0.owner === button })
        XCTAssertTrue(area.options.contains([.activeAlways, .enabledDuringMouseDrag]))
        XCTAssertEqual(area.rect, button.bounds.intersection(button.visibleRect))
        XCTAssertLessThanOrEqual(area.rect.width, button.bounds.width)
        panel.pointer = CGPoint(x: 15, y: 15)
        button.updateTrackingAreas()
        XCTAssertGreaterThan(feedback.layer?.sublayerTransform.m11 ?? 0, 1, hoverDiagnostics(button))
        button.updateTrackingAreas()
        XCTAssertEqual(button.trackingAreas.filter { $0.owner === button }.count, 1)
        panel.pointer = CGPoint(x: 80, y: 80)
        button.updateTrackingAreas()
        XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
    }

    func testSurfaceCallbacksReadReducedMotionForEachInteraction() throws {
        var reduced = false
        let (panel, button) = makeFixture(reduceMotion: { reduced })
        defer { panel.close() }
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let face = try XCTUnwrap(feedback.subviews.first)
        panel.pointer = CGPoint(x: 15, y: 15)
        button.updateTrackingAreas()
        XCTAssertGreaterThan(feedback.layer?.sublayerTransform.m11 ?? 0, 1)

        reduced = true
        button.highlight(true)
        button.updateLayer()
        XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
        XCTAssertEqual(face.layer?.borderWidth, 1.5)
        XCTAssertTrue((feedback.layer?.animationKeys() ?? []).isEmpty)
        button.highlight(false)
        button.updateLayer()
        XCTAssertEqual(face.layer?.borderWidth, 1)
        panel.pointer = CGPoint(x: 80, y: 80)
        button.updateTrackingAreas()
        XCTAssertEqual(face.layer?.borderWidth, 0)

        reduced = false
        panel.pointer = CGPoint(x: 15, y: 15)
        button.updateTrackingAreas()
        XCTAssertGreaterThan(feedback.layer?.sublayerTransform.m11 ?? 0, 1)
        XCTAssertEqual(face.layer?.borderWidth, 0)
    }

    func testUnattachedButtonIgnoresPointerHover() throws {
        let button = try XCTUnwrap(button() as? HoverOverlayButtonView)
        let surface = HoverControlAppearance.makeSurface(for: button, reduceMotion: { false })
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let face = try XCTUnwrap(feedback.subviews.first)
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: CGPoint(x: 15, y: 15), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        withExtendedLifetime(surface) {
            XCTAssertNil(button.window)
            button.updateTrackingAreas()
            button.mouseEntered(with: entered)
            XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
            XCTAssertEqual(face.layer?.borderWidth, 0)
            XCTAssertTrue((feedback.layer?.animationKeys() ?? []).isEmpty)
        }
    }

    func testHideDisableAndRemovalResetHover() throws {
        let (panel, button) = makeFixture()
        defer { panel.close() }
        let feedback = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        panel.pointer = CGPoint(x: 15, y: 15)
        button.updateTrackingAreas()
        button.isEnabled = false
        XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
        button.isEnabled = true
        XCTAssertGreaterThan(feedback.layer?.sublayerTransform.m11 ?? 0, 1, hoverDiagnostics(button))
        button.isHidden = true
        XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
        button.isHidden = false
        button.updateTrackingAreas()
        XCTAssertGreaterThan(feedback.layer?.sublayerTransform.m11 ?? 0, 1, hoverDiagnostics(button))
        button.removeFromSuperview()
        XCTAssertEqual(feedback.layer?.sublayerTransform.m11, 1)
    }

    func testMouseMovesBetweenButtonsIndependently() throws {
        let (firstPanel, first) = makeFixture()
        let (secondPanel, second) = makeFixture()
        defer { firstPanel.close(); secondPanel.close() }
        let firstFeedback = try XCTUnwrap(first.superview as? HoverButtonPressFeedback)
        let secondFeedback = try XCTUnwrap(second.superview as? HoverButtonPressFeedback)
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: CGPoint(x: 15, y: 15), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        let exited = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited, location: CGPoint(x: 60, y: 15), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        first.mouseEntered(with: entered)
        XCTAssertGreaterThan(firstFeedback.layer?.sublayerTransform.m11 ?? 0, 1, hoverDiagnostics(first))
        XCTAssertEqual(secondFeedback.layer?.sublayerTransform.m11, 1)
        first.mouseExited(with: exited)
        second.mouseEntered(with: entered)
        XCTAssertEqual(firstFeedback.layer?.sublayerTransform.m11, 1)
        XCTAssertGreaterThan(secondFeedback.layer?.sublayerTransform.m11 ?? 0, 1, hoverDiagnostics(second))
    }
}
