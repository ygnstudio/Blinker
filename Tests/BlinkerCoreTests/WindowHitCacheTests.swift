@testable import BlinkerCore
import CoreGraphics
import XCTest

final class WindowHitCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AXQuery.invalidateWindowUnderPointCache()
    }

    override func tearDown() {
        AXQuery.invalidateWindowUnderPointCache()
        super.tearDown()
    }

    func testMovingFromExposedBackgroundIntoOverlapUsesFrontWindow() {
        for foregroundPID: pid_t in [10, 20] {
            AXQuery.invalidateWindowUnderPointCache()
            let back = info(id: 1, pid: 10, originX: 0)
            let front = info(id: 2, pid: foregroundPID, originX: 100)
            var queries: [(CGWindowListOption, CGWindowID)] = []
            let provider: AXQuery.WindowListProvider = { options, windowID in
                queries.append((options, windowID))
                // Simulates the old single-window query as well as a z-order query.
                if options.contains(.optionIncludingWindow), !options.contains(.optionOnScreenAboveWindow) {
                    return [back]
                }
                return [front, back]
            }
            XCTAssertEqual(AXQuery.windowUnderPoint(
                CGPoint(x: 50, y: 50), usingCache: true, windowList: provider
            )?.windowID, 1)
            XCTAssertEqual(AXQuery.windowUnderPoint(
                CGPoint(x: 150, y: 50), usingCache: true, windowList: provider
            )?.windowID, 2)
            XCTAssertTrue(queries[1].0.contains(.optionOnScreenAboveWindow))
            XCTAssertEqual(queries[1].1, 1)
        }
    }

    func testExcludedForegroundWindowBlocksCachedBackground() {
        let back = info(id: 1, pid: 10, originX: 0)
        let front = info(id: 2, pid: 99, originX: 100)
        let provider: AXQuery.WindowListProvider = { _, _ in [front, back] }
        XCTAssertNotNil(AXQuery.windowUnderPoint(
            CGPoint(x: 50, y: 50), excludingProcessIdentifier: 99,
            usingCache: true, windowList: provider
        ))
        XCTAssertNil(AXQuery.windowUnderPoint(
            CGPoint(x: 150, y: 50), excludingProcessIdentifier: 99,
            usingCache: true, windowList: provider
        ))
    }

    func testVanishedCachedWindowFallsBackToFullList() {
        let back = info(id: 1, pid: 10, originX: 0)
        let replacement = info(id: 2, pid: 10, originX: 0)
        _ = AXQuery.windowUnderPoint(CGPoint(x: 50, y: 50), usingCache: true, windowList: { _, _ in [back] })
        let result = AXQuery.windowUnderPoint(CGPoint(x: 50, y: 50), usingCache: true) { options, _ in
            options.contains(.optionOnScreenAboveWindow) ? [] : [replacement]
        }
        XCTAssertEqual(result?.windowID, 2)
    }

    func testVisibleOwnerMustKeepIdentityBoundsAndOnscreenStatus() {
        let expected = AXQuery.WindowHit(
            processIdentifier: 10, bounds: CGRect(x: 0, y: 0, width: 300, height: 300), windowID: 1
        )
        XCTAssertTrue(AXQuery.isWindowCurrent(
            expected,
            windowList: { _, _ in [self.info(id: 1, pid: 10, originX: 0)] }
        ))
        let stale = [
            info(id: 2, pid: 10, originX: 0), info(id: 1, pid: 20, originX: 0), info(
                id: 1,
                pid: 10,
                originX: 1
            ),
            info(id: 1, pid: 10, originX: 0, onscreen: false),
        ]
        for entry in stale {
            XCTAssertFalse(AXQuery.isWindowCurrent(expected, windowList: { _, _ in [entry] }))
        }
        XCTAssertFalse(AXQuery.isWindowCurrent(expected, windowList: { _, _ in [] }))
    }

    private func info(id: CGWindowID, pid: pid_t, originX: CGFloat, onscreen: Bool = true) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowIsOnscreen as String: onscreen,
            kCGWindowBounds as String: CGRect(x: originX, y: 0, width: 300, height: 300)
                .dictionaryRepresentation,
        ]
    }
}
