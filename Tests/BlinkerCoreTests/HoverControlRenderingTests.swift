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
}
