import AppKit
@testable import BlinkerCore
import XCTest

final class WindowBrowserKeyRoutingTests: XCTestCase {
    private let active = WindowBrowserKeyRouting.Context(isOpen: true, isKeyWindow: true, rowStep: 4)

    func testNavigationAndWindowActionsAreConsumedExactlyOnce() throws {
        let cases: [(NSEvent, WindowBrowserKeyRouting.Action)] = try [
            (event(key: 123), .move(-1)), (event(key: 124), .move(1)),
            (event(key: 125), .move(4)), (event(key: 126), .move(-4)),
            (event(key: 48), .move(1)), (event(key: 48, modifiers: [.shift]), .move(-1)),
            (event(key: 53), .dismiss), (event(key: 36), .commit), (event(key: 76), .commit),
            (event(key: 13, modifiers: [.command]), .perform(.closeWindow)),
            (event(key: 46, modifiers: [.command]), .perform(.minimize)),
        ]
        for (input, expected) in cases {
            var actions: [WindowBrowserKeyRouting.Action] = []
            let forwarded = WindowBrowserKeyRouting.route(input, context: active) { actions.append($0) }
            XCTAssertNil(forwarded, "handled key \(input.keyCode) must not reach another responder")
            XCTAssertEqual(actions, [expected])
        }
    }

    func testUnhandledTypingAndInactivePanelsPassThroughTheOriginalEvent() throws {
        let cases: [(NSEvent, WindowBrowserKeyRouting.Context?)] = try [
            (event(key: 0), active),
            (event(key: 13), active),
            (event(key: 46), active),
            (event(key: 48), nil),
            (event(key: 48), .init(isOpen: false, isKeyWindow: true, rowStep: 4)),
            (event(key: 48), .init(isOpen: true, isKeyWindow: false, rowStep: 4)),
            (event(key: 48, type: .keyUp), active),
        ]
        for (input, context) in cases {
            let forwarded = WindowBrowserKeyRouting.route(input, context: context) { _ in
                XCTFail("an unhandled event must not dispatch a browser action")
            }
            XCTAssertTrue(forwarded === input)
        }
    }

    func testModifierReleaseIsObservedWithoutConsumingFlagsEvents() throws {
        let background = WindowBrowserKeyRouting.Context(isOpen: true, isKeyWindow: false, rowStep: 1)
        for modifiers: NSEvent.ModifierFlags in [[], [.shift], [.option], [.option, .shift]] {
            let input = try event(key: 58, modifiers: modifiers, type: .flagsChanged)
            var actions: [WindowBrowserKeyRouting.Action] = []
            let forwarded = WindowBrowserKeyRouting.route(input, context: background) { actions.append($0) }
            XCTAssertTrue(forwarded === input)
            XCTAssertEqual(actions, modifiers.contains(.option) ? [] : [.releaseOption])
        }
    }

    private func event(key: UInt16, modifiers: NSEvent.ModifierFlags = [],
                       type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                       timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                       charactersIgnoringModifiers: "", isARepeat: false, keyCode: key))
    }
}
