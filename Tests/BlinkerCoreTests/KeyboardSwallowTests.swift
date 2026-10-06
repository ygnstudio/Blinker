@testable import BlinkerCore
import XCTest

final class KeyboardSwallowTests: XCTestCase {
    func testHandlesKeyboardAndSystemDefinedTypes() {
        XCTAssertTrue(KeyboardSwallow.handles(KeyboardSwallow.keyDownType))
        XCTAssertTrue(KeyboardSwallow.handles(KeyboardSwallow.keyUpType))
        XCTAssertTrue(KeyboardSwallow.handles(KeyboardSwallow.flagsChangedType))
        XCTAssertTrue(KeyboardSwallow.handles(KeyboardSwallow.systemDefinedType))
        XCTAssertFalse(KeyboardSwallow.handles(13)) // null/event types outside the mask
        XCTAssertFalse(KeyboardSwallow.handles(0))
        XCTAssertFalse(KeyboardSwallow.handles(5)) // mouseMoved
    }

    func testSwallowsAllPlainKeyboardEvents() {
        for type in [KeyboardSwallow.keyDownType, KeyboardSwallow.keyUpType,
                     KeyboardSwallow.flagsChangedType] {
            XCTAssertTrue(KeyboardSwallow.swallows(eventType: type, isMediaKeySubtype: false))
            XCTAssertTrue(KeyboardSwallow.swallows(eventType: type, isMediaKeySubtype: true))
        }
    }

    func testSwallowsOnlyMediaSubtypeAmongSystemDefined() {
        XCTAssertTrue(KeyboardSwallow.swallows(eventType: KeyboardSwallow.systemDefinedType,
                                               isMediaKeySubtype: true))
        XCTAssertFalse(KeyboardSwallow.swallows(eventType: KeyboardSwallow.systemDefinedType,
                                                isMediaKeySubtype: false))
    }

    func testNeverSwallowsUnhandledTypes() {
        XCTAssertFalse(KeyboardSwallow.swallows(eventType: 13, isMediaKeySubtype: true))
        XCTAssertFalse(KeyboardSwallow.swallows(eventType: 5, isMediaKeySubtype: false))
    }
}
