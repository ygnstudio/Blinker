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

    func testPreviewUsesTheLiveButtonClass() {
        let preview = HoverControlAppearance.makePreviewButton(
            frame: CGRect(x: 0, y: 0, width: 48, height: 48),
            action: .closeWindow, color: .systemRed
        )
        XCTAssertTrue(preview is HoverOverlayButtonView)
    }
}
