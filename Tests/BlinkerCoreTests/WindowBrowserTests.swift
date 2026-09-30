@testable import BlinkerCore
import CoreGraphics
import XCTest

final class WindowBrowserTests: XCTestCase {
    func testAXReadBudgetBoundsRequestCountAndRemainingDeadline() throws {
        var instant: TimeInterval = 100
        var budget = WindowAXReadBudget(duration: 0.1, requests: 3, now: { instant })
        XCTAssertEqual(try XCTUnwrap(budget.nextTimeout()), 0.04, accuracy: 0.0001)
        instant += 0.08
        XCTAssertEqual(try XCTUnwrap(budget.nextTimeout()), 0.02, accuracy: 0.0001)
        instant += 0.03
        XCTAssertNil(budget.nextTimeout())
        XCTAssertFalse(budget.isAvailable)
        var requests = WindowAXReadBudget(duration: 10, requests: 1, now: { instant })
        XCTAssertNotNil(requests.nextTimeout())
        XCTAssertNil(requests.nextTimeout())
    }

    func testStandardDocumentTabsAcceptDuplicateTitlesWithoutAppAllowlist() {
        let tabs = [WindowTabDiscovery.StandardTabDescriptor(title: "Untitled", selected: true,
                                                             hasCloseControl: true),
                    WindowTabDiscovery.StandardTabDescriptor(title: "Untitled", selected: false,
                                                             hasCloseControl: true)]
        XCTAssertTrue(WindowTabDiscovery.isDocumentTabBar(isWindowChild: true, tabs: tabs))
        XCTAssertFalse(WindowTabDiscovery.isDocumentTabBar(isWindowChild: false, tabs: tabs))
    }

    func testSettingsTabViewsAndAmbiguousTabSelectionAreNotDocumentTabs() {
        let ordinary = [WindowTabDiscovery.StandardTabDescriptor(title: "General", selected: true,
                                                                 hasCloseControl: false),
                        WindowTabDiscovery.StandardTabDescriptor(title: "Advanced", selected: false,
                                                                 hasCloseControl: false)]
        XCTAssertFalse(WindowTabDiscovery.isDocumentTabBar(isWindowChild: true, tabs: ordinary))
        let selected = WindowTabDiscovery.StandardTabDescriptor(title: "Document", selected: true,
                                                                hasCloseControl: true)
        XCTAssertFalse(WindowTabDiscovery.isDocumentTabBar(isWindowChild: true, tabs: [selected, selected]))
        XCTAssertFalse(WindowTabDiscovery.isDocumentTabBar(isWindowChild: true, tabs: []))
        XCTAssertFalse(WindowTabDiscovery.isDocumentTabBar(isWindowChild: true, tabs: [selected]))
    }

    func testCaptureMatchingRejectsAmbiguousAndWrongApplicationWindows() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let first: [String: Any] = [kCGWindowOwnerPID as String: Int32(42),
                                    kCGWindowLayer as String: 0, kCGWindowNumber as String: UInt32(10),
                                    kCGWindowBounds as String: frame.dictionaryRepresentation,
                                    kCGWindowName as String: "Document"]
        var second = first
        second[kCGWindowNumber as String] = UInt32(11)
        XCTAssertNil(WindowDiscovery.captureMatch([first, second], pid: 42, frame: frame, title: "Document"))
        XCTAssertNil(WindowDiscovery.captureMatch([first], pid: 99, frame: frame, title: "Document"))
        second[kCGWindowName as String] = "Other"
        let match = WindowDiscovery.captureMatch([first, second], pid: 42, frame: frame, title: "Other")
        XCTAssertEqual(match?[kCGWindowNumber as String] as? UInt32, 11)
    }

    func testMinimizedCaptureMatchesUniqueTitleWhenFrameIsUnavailable() {
        let surface: [String: Any] = [kCGWindowOwnerPID as String: Int32(42),
                                      kCGWindowLayer as String: 0, kCGWindowNumber as String: UInt32(10),
                                      kCGWindowBounds as String: CGRect.zero.dictionaryRepresentation,
                                      kCGWindowName as String: "Document"]
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertNil(WindowDiscovery.captureMatch([surface], pid: 42,
                                                  frame: frame, title: "Document"))
        let match = WindowDiscovery.captureMatch([surface], pid: 42, frame: frame, title: "Document",
                                                 allowOffscreenTitleMatch: true)
        XCTAssertEqual(match?[kCGWindowNumber as String] as? UInt32, 10)
        XCTAssertNil(WindowDiscovery.captureMatch(
            [surface, surface],
            pid: 42,
            frame: frame,
            title: "Document",
            allowOffscreenTitleMatch: true
        ))
        XCTAssertNil(WindowDiscovery.captureMatch([surface], pid: 99, frame: frame, title: "Document",
                                                  allowOffscreenTitleMatch: true))
        XCTAssertNil(WindowDiscovery.captureMatch([surface], pid: 42, frame: frame, title: "",
                                                  allowOffscreenTitleMatch: true))
    }

    func testPreviewSizeScalesImagesAndKeepsLargeGridWithinSmallScreen() {
        let screen = CGSize(width: 1440, height: 900)
        let small = WindowBrowserGeometry.previewLayout(windowCount: 1, scale: 0.5, screenSize: screen)
        let large = WindowBrowserGeometry.previewLayout(windowCount: 1, scale: 1.5, screenSize: screen)
        XCTAssertEqual(small.thumbnailHeight, 110)
        XCTAssertEqual(small.size.width, 128)
        XCTAssertLessThan(small.size.width, large.size.width)
        XCTAssertEqual(small.size.width * 3, large.size.width)
        XCTAssertEqual(small.size.height * 3, large.size.height)
        for count in [1, 3, 6, 8, 15] {
            let layout = WindowBrowserGeometry.previewLayout(windowCount: count, scale: 1.5,
                                                             screenSize: CGSize(width: 640, height: 480))
            XCTAssertLessThanOrEqual(layout.size.width, 620)
            XCTAssertLessThanOrEqual(layout.size.height, 460)
            let rows = CGFloat(layout.rows)
            if layout.thumbnailHeight > 44 {
                XCTAssertLessThanOrEqual((rows * (layout.thumbnailHeight + 64) + 80) * 1.5, 460.001)
            }
        }
        let eight = WindowBrowserGeometry.previewLayout(windowCount: 8, scale: 0.5, screenSize: screen)
        XCTAssertEqual(eight.columns, 4)
        XCTAssertEqual(eight.rows, 2)
        let invalid = WindowBrowserGeometry.previewLayout(windowCount: 1, scale: .nan, screenSize: screen)
        let normal = WindowBrowserGeometry.previewLayout(windowCount: 1, scale: 1, screenSize: screen)
        XCTAssertEqual(invalid.size, normal.size)
    }

    func testSelectionWrapsForwardAndBackward() {
        let ids = (0 ..< 4).map { _ in UUID() }
        var selection = WindowBrowserSelection()
        selection.replace(ids)
        selection.move(-1)
        XCTAssertEqual(selection.selected, ids[3])
        selection.move(1)
        XCTAssertEqual(selection.selected, ids[0])
        selection.move(10)
        XCTAssertEqual(selection.selected, ids[2])
    }

    func testRefreshPreservesSelectedWindowRatherThanArrayIndex() {
        let ids = (0 ..< 4).map { _ in UUID() }
        var selection = WindowBrowserSelection()
        selection.replace(ids, preferred: ids[2])
        selection.replace([ids[2], ids[0], ids[3]])
        XCTAssertEqual(selection.selected, ids[2])
    }

    func testClosingSelectedWindowSelectsItsNeighbor() {
        let ids = (0 ..< 3).map { _ in UUID() }
        var selection = WindowBrowserSelection()
        selection.replace(ids, preferred: ids[1])
        selection.replace([ids[0], ids[2]])
        XCTAssertEqual(selection.selected, ids[2])
        selection.replace([])
        selection.move(-1)
        XCTAssertNil(selection.selected)
    }

    func testDockPanelsStayOnNegativeCoordinateDisplayForEveryDockEdge() {
        let screen = CGRect(x: -1400, y: 200, width: 1400, height: 1000)
        let anchors = [CGRect(x: -800, y: 200, width: 50, height: 50),
                       CGRect(x: -1400, y: 900, width: 50, height: 50),
                       CGRect(x: -50, y: 900, width: 50, height: 50)]
        for anchor in anchors {
            let frame = WindowBrowserGeometry.panelFrame(size: CGSize(width: 720, height: 464),
                                                         anchor: anchor, screen: screen)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertFalse(frame.intersects(anchor))
        }
    }

    func testOversizedBrowserFitsSmallDisplay() {
        let screen = CGRect(x: 800, y: -600, width: 600, height: 400)
        let frame = WindowBrowserGeometry.panelFrame(size: CGSize(width: 900, height: 700),
                                                     anchor: nil, screen: screen)
        XCTAssertEqual(frame, screen.insetBy(dx: 10, dy: 10))
    }

    func testThirdsCoverLandscapeAndPortraitWithoutOverlap() {
        for screen in [CGRect(x: -1200, y: 100, width: 1200, height: 900),
                       CGRect(x: 200, y: -1200, width: 900, height: 1200)] {
            let first = WindowGeometry.tiledFrame(.firstThird, in: screen)
            let middle = WindowGeometry.tiledFrame(.centerThird, in: screen)
            let last = WindowGeometry.tiledFrame(.lastThird, in: screen)
            XCTAssertEqual(first.union(middle).union(last), screen)
            XCTAssertEqual(first.width * first.height * 3, screen.width * screen.height, accuracy: 0.001)
            XCTAssertEqual(WindowGeometry.tiledFrame(.firstTwoThirds, in: screen), first.union(middle))
            XCTAssertEqual(WindowGeometry.tiledFrame(.lastTwoThirds, in: screen), middle.union(last))
            if screen.height > screen.width {
                XCTAssertGreaterThan(first.minY, last.minY)
            }
        }
    }

    func testDisplayTransferPreservesRelativePositionAndCapsSize() {
        let source = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let target = CGRect(x: -1000, y: -500, width: 1000, height: 700)
        let topRight = CGRect(x: 600, y: 400, width: 600, height: 500)
        let result = WindowGeometry.transferredFrame(topRight, from: source, to: target)
        XCTAssertEqual(result.maxX, target.maxX)
        XCTAssertEqual(result.maxY, target.maxY)
        XCTAssertEqual(result.size, topRight.size)
        XCTAssertEqual(WindowGeometry.transferredFrame(source, from: source, to: target), target)
    }
}
