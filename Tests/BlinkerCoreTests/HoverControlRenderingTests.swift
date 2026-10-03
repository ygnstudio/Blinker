import AppKit
@testable import BlinkerCore
import XCTest

@MainActor
final class HoverControlRenderingTests: XCTestCase {
    func testLiveButtonKeepsNativeLayerRenderingInNonactivatingPanel() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass requires macOS 26") }
        _ = NSApplication.shared
        let frame = CGRect(x: 100, y: 100, width: 48, height: 48)
        let button = HoverOverlayButtonView(
            frame: CGRect(origin: .zero, size: frame.size), symbol: "xmark",
            label: "Close", color: .systemRed, onActivate: { _ in }
        )
        let trayFrame = try XCTUnwrap(HoverOverlayTrayPanel.frame(forDisplayFrames: [frame]))
        let panel = HoverOverlayTrayPanel(trayFrame: trayFrame)
        panel.update(trayFrame: trayFrame, controls: [button], frames: [frame])
        panel.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(panel.contentView?.wantsLayer, true)
        // Overriding NSButton.draw makes this false and drops the glass bezel.
        XCTAssertTrue(button.wantsUpdateLayer)
        button.setDwellProgress(0.5)
        XCTAssertTrue(button.wantsUpdateLayer)
        XCTAssertIdentical(button.hitTest(CGPoint(x: 24, y: 24)), button)
        button.resetDwell()
        XCTAssertTrue(button.wantsUpdateLayer)
    }

    func testMappedActionUpdatesTooltipAndAccessibilityTogether() {
        let button = HoverOverlayButtonView(
            frame: CGRect(x: 0, y: 0, width: 40, height: 40), symbol: "xmark",
            label: "Close", color: .systemRed, onActivate: { _ in }
        )
        button.updatePresentation(OverlayActionPresentation(action: .quitApp))
        XCTAssertEqual(button.toolTip, ButtonAction.quitApp.localizedLabel)
        XCTAssertEqual(button.accessibilityLabel(), ButtonAction.quitApp.localizedLabel)
        button.updatePresentation(OverlayActionPresentation(action: .minimize))
        XCTAssertEqual(button.toolTip, ButtonAction.minimize.localizedLabel)
    }

    func testClickProtectionCanBeLimitedToConfiguredActions() throws {
        var activations = 0
        let button = HoverOverlayButtonView(
            frame: CGRect(x: 0, y: 0, width: 40, height: 40), symbol: "xmark",
            label: "Close", color: .systemRed, onActivate: { _ in activations += 1 }
        )
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        button.requiresDwell = { _ in false }
        button.rightMouseDown(with: event)
        XCTAssertEqual(activations, 1)
        button.requiresDwell = { _ in true }
        button.rightMouseDown(with: event)
        XCTAssertEqual(activations, 1)
        button.setDwellProgress(1)
        button.rightMouseDown(with: event)
        XCTAssertEqual(activations, 2)
    }

    func testDisabledButtonCannotBypassNativeTrackingThroughRightClick() throws {
        var activations = 0
        let button = HoverOverlayButtonView(
            frame: CGRect(x: 0, y: 0, width: 40, height: 40), symbol: "xmark",
            label: "Close", color: .systemRed, onActivate: { _ in activations += 1 }
        )
        button.requiresDwell = { _ in false }
        button.setDwellProgress(1)
        button.isEnabled = false
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))

        button.rightMouseDown(with: event)

        XCTAssertEqual(activations, 0)
    }

    func testProtectedPressDoesNotGiveReadyFeedbackOrActivate() throws {
        var activations = 0
        var pressChanges = 0
        let button = HoverOverlayButtonView(
            frame: CGRect(x: 0, y: 0, width: 40, height: 40), symbol: "xmark",
            label: "Close", color: .systemRed, onActivate: { _ in activations += 1 }
        )
        button.onPressChanged = { _, _ in pressChanges += 1 }
        button.setDwellProgress(0.5)
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            if type == .leftMouseDown {
                button.mouseDown(with: event)
            } else {
                button.rightMouseDown(with: event)
            }
        }
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(pressChanges, 0)
    }

    func testNativeHighlightDrivesFeedbackWithoutChangingHitAreaOrColor() throws {
        var activations = 0
        let frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let button = HoverOverlayButtonView(
            frame: frame, symbol: "xmark", label: "Close", color: .systemRed,
            onActivate: { _ in activations += 1 }
        )
        let surface = HoverControlAppearance.makeSurface(for: button)
        let content = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let face = try XCTUnwrap(content.subviews.first)
        face.updateLayer()
        let color = face.layer?.backgroundColor

        button.isHighlighted = true
        button.updateLayer()

        XCTAssertEqual(face.layer?.borderWidth, 1.5)
        XCTAssertEqual(button.frame, frame)
        XCTAssertEqual(surface.frame, frame)
        XCTAssertIdentical(button.hitTest(CGPoint(x: 1, y: 20)), button)
        XCTAssertTrue(button.wantsUpdateLayer)
        XCTAssertEqual(face.layer?.backgroundColor, color)
        XCTAssertEqual(activations, 0)

        button.isHighlighted = false
        button.updateLayer()
        XCTAssertEqual(face.layer?.borderWidth, 0)
        XCTAssertEqual(content.layer?.sublayerTransform.m11, 1)
        XCTAssertEqual(activations, 0)
    }

    func testReleaseIsInterruptibleAndReduceMotionKeepsAStaticPressedSignal() throws {
        let button = HoverControlAppearance.makePreviewButton(
            frame: CGRect(x: 0, y: 0, width: 40, height: 40), action: .closeWindow, color: .systemRed
        )
        let surface = HoverControlAppearance.makeSurface(for: button)
        let content = try XCTUnwrap(button.superview as? HoverButtonPressFeedback)
        let layer = try XCTUnwrap(content.layer)
        let face = try XCTUnwrap(content.subviews.first)
        let frame = button.frame
        withExtendedLifetime(surface) {
            content.setPressed(true, reduceMotion: false, animated: false)
            XCTAssertLessThan(layer.sublayerTransform.m11, 1)
            XCTAssertEqual(
                content.bounds.midX * layer.sublayerTransform.m11 + layer.sublayerTransform.m41,
                content.bounds.midX, accuracy: 0.001
            )
            XCTAssertEqual(
                content.bounds.midY * layer.sublayerTransform.m22 + layer.sublayerTransform.m42,
                content.bounds.midY, accuracy: 0.001
            )
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
            content.setPressed(false, reduceMotion: false, animated: true)
            XCTAssertEqual(layer.sublayerTransform.m11, 1)
            XCTAssertEqual(layer.animationKeys()?.count, 1)

            // A second press cancels the outgoing animation instead of queuing it.
            content.setPressed(true, reduceMotion: false, animated: false)
            XCTAssertLessThan(layer.sublayerTransform.m11, 1)
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
            content.setPressed(true, reduceMotion: true, animated: true)
            XCTAssertEqual(layer.sublayerTransform.m11, 1)
            XCTAssertGreaterThan(face.layer?.borderWidth ?? 0, 0)
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
            content.setPressed(false, reduceMotion: true, animated: true)
            XCTAssertEqual(layer.sublayerTransform.m11, 1)
            XCTAssertEqual(face.layer?.borderWidth, 0)
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
            XCTAssertEqual(button.frame, frame)
        }
    }

    func testContinuousGlassTrayCoversGapsAndResizesWithPalette() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass requires macOS 26") }
        _ = NSApplication.shared
        let frames = [CGRect(x: 100, y: 100, width: 28, height: 28),
                      CGRect(x: 132, y: 100, width: 28, height: 28)]
        let trayFrame = try XCTUnwrap(HoverOverlayTrayPanel.frame(forDisplayFrames: frames))
        let panel = HoverOverlayTrayPanel(trayFrame: trayFrame)
        let buttons = frames.map { frame in
            HoverControlAppearance.makePreviewButton(frame: frame, action: .closeWindow, color: .systemRed)
        }
        panel.update(trayFrame: trayFrame, controls: buttons, frames: frames)
        let root = try XCTUnwrap(panel.contentView)
        let tray = try XCTUnwrap(root.subviews.first as? NSGlassEffectView)
        XCTAssertEqual(tray.frame, root.bounds)
        // A glass grouping container alone cannot render this gap or the padding.
        XCTAssertTrue(tray.frame.contains(CGPoint(x: 42, y: 22)))
        XCTAssertTrue(root.subviews.last is NSGlassEffectContainerView)
        let largerFrame = trayFrame.insetBy(dx: -20, dy: -10)
        panel.update(trayFrame: largerFrame, controls: buttons, frames: frames)
        XCTAssertEqual(tray.frame.size, largerFrame.size)
        XCTAssertEqual(tray.cornerRadius, largerFrame.height / 2)
        XCTAssertTrue(buttons.allSatisfy { $0.bezelColor == .systemRed })
    }

    func testPreviewUsesTheLiveButtonClass() {
        let preview = HoverControlAppearance.makePreviewButton(
            frame: CGRect(x: 0, y: 0, width: 48, height: 48),
            action: .closeWindow, color: .systemRed
        )
        XCTAssertTrue(preview is HoverOverlayButtonView)
    }

    func testSemanticColorsStayOpaqueInInactiveGlassInBothAppearances() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass requires macOS 26") }
        _ = NSApplication.shared
        let colors = TrafficButton.allCases.map(OverlayChipDrawing.vividColor) + [.controlAccentColor]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for color in colors {
                let frame = CGRect(x: 100, y: 100, width: 40, height: 40)
                let button = HoverControlAppearance.makePreviewButton(
                    frame: frame, action: .closeWindow, color: color
                )
                let trayFrame = try XCTUnwrap(HoverOverlayTrayPanel.frame(forDisplayFrames: [frame]))
                let panel = HoverOverlayTrayPanel(trayFrame: trayFrame)
                panel.appearance = NSAppearance(named: appearance)
                panel.update(trayFrame: trayFrame, controls: [button], frames: [frame])
                panel.contentView?.layoutSubtreeIfNeeded()
                let content = try XCTUnwrap(button.superview)
                let face = try XCTUnwrap(content.subviews.first { $0 !== button })
                var ancestor = content.superview
                while let view = ancestor, !(view is NSGlassEffectView) {
                    ancestor = view.superview
                }
                let glass = try XCTUnwrap(ancestor as? NSGlassEffectView)
                XCTAssertFalse(panel.isKeyWindow)
                XCTAssertLessThan(face.bounds.width, glass.bounds.width, "the native glass rim stays exposed")
                XCTAssertEqual(glass.tintColor, color)
                var actualColor: NSColor?
                var expectedColor: NSColor?
                panel.effectiveAppearance.performAsCurrentDrawingAppearance {
                    face.updateLayer()
                    actualColor = face.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }?
                        .usingColorSpace(.sRGB)
                    expectedColor = color.usingColorSpace(.sRGB)
                }
                let resolved = try XCTUnwrap(actualColor)
                let expected = try XCTUnwrap(expectedColor)
                XCTAssertEqual(resolved.alphaComponent, 1, accuracy: 0.001,
                               "the dark backdrop must not dilute the semantic button color")
                XCTAssertEqual(resolved.redComponent, expected.redComponent, accuracy: 0.001)
                XCTAssertEqual(resolved.greenComponent, expected.greenComponent, accuracy: 0.001)
                XCTAssertEqual(resolved.blueComponent, expected.blueComponent, accuracy: 0.001)
            }
        }
    }
}
