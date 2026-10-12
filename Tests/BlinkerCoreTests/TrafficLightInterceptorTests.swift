@testable import BlinkerCore
import CoreGraphics
import XCTest

final class TrafficLightInterceptorTests: XCTestCase {
    override func tearDown() {
        HoverTestWindow.register(windowID: nil)
        AXQuery.invalidateWindowUnderPointCache()
        super.tearDown()
    }

    func testOwnForegroundWindowBlocksGlobalRemappingAndWindowsBehindIt() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = [info(id: 1, pid: ownPID), info(id: 2, pid: ownPID + 1)]
        XCTAssertNil(TrafficLightInterceptor.interceptableWindow(
            at: CGPoint(x: 20, y: 20), windowList: { _, _ in windows }
        ))
    }

    func testRegisteredHoverTestWindowStillKeepsNativeTrafficLightClicks() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        HoverTestWindow.register(windowID: 71)
        let windows = [info(id: 71, pid: ownPID), info(id: 2, pid: ownPID + 1)]
        XCTAssertNil(TrafficLightInterceptor.interceptableWindow(
            at: CGPoint(x: 20, y: 20), windowList: { _, _ in windows }
        ))
    }

    func testForeignForegroundWindowRemainsEligibleWhenBlinkerIsBehindIt() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = [info(id: 2, pid: ownPID + 1), info(id: 1, pid: ownPID)]
        let result = TrafficLightInterceptor.interceptableWindow(
            at: CGPoint(x: 20, y: 20), windowList: { _, _ in windows }
        )
        XCTAssertEqual(result?.windowID, 2)
        XCTAssertEqual(result?.processIdentifier, ownPID + 1)
    }

    private func info(id: CGWindowID, pid: pid_t) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowIsOnscreen as String: true,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 300, height: 300)
                .dictionaryRepresentation,
        ]
    }
}
