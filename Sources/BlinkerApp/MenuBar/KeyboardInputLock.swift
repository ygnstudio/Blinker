import AppKit
import BlinkerCore
import CoreGraphics
import os
import QuartzCore

/// System-level keyboard lock behind a CGEvent tap. Window-level key capture
/// only receives events while the app is active and its window is key, which
/// a menu-bar app cannot guarantee — every serious keyboard cleaner (Cleankey,
/// Zandaa1/keyboard-cleaner, kb-clean) uses a tap for this reason. Swallow
/// policy itself lives in BlinkerCore.KeyboardSwallow; this type owns the tap
/// lifecycle.
///
/// The tap's run-loop source is installed on the main run loop, so the C
/// callback executes on the main thread; mutable state still goes through a
/// lock because the compiler cannot see that. `start`/`stop` must be called
/// on the main thread.
final class KeyboardInputLock: @unchecked Sendable {
    enum Mode {
        /// Display cleaning: a single Escape exits.
        case display
        /// Keyboard cleaning: Escape ×3 is the emergency exit, matching the
        /// upstream convention so a stuck UI can never lock the user out.
        case keyboard

        var escapeThreshold: Int {
            switch self {
            case .display: 1
            case .keyboard: 3
            }
        }
    }

    private struct State {
        var tap: CFMachPort?
        var runLoopSource: CFRunLoopSource?
        var escape = EscapeSequence(threshold: 1, window: 1.5)
        var onEscape: (() -> Void)?
    }

    private static let escapeWindow: TimeInterval = 1.5
    private let shared = OSAllocatedUnfairLock(initialState: State())

    /// Installs and enables the tap. `onEscape` fires (main queue) when the
    /// mode's Escape sequence completes. Returns false when the tap cannot be
    /// created — with both permissions granted but stale (granted for an
    /// older binary), macOS may deny creation until relaunch.
    @discardableResult
    func start(mode: Mode, onEscape: @escaping () -> Void) -> Bool {
        shared.withLock { state in
            guard state.tap == nil else { return true }
            let types = [KeyboardSwallow.keyDownType, KeyboardSwallow.keyUpType,
                         KeyboardSwallow.flagsChangedType, KeyboardSwallow.systemDefinedType]
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: KeyboardInputLock.tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { return false }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            state.tap = tap
            state.runLoopSource = source
            state.escape = EscapeSequence(threshold: mode.escapeThreshold,
                                          window: Self.escapeWindow)
            state.onEscape = onEscape
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
    }

    /// Removes the tap; invalidating the Mach port avoids leaking one per
    /// cleaning session (upstream teardown does the same).
    func stop() {
        shared.withLock { state in
            Self.teardown(&state)
        }
    }

    private static func teardown(_ state: inout State) {
        if let source = state.runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            state.runLoopSource = nil
        }
        if let tap = state.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            state.tap = nil
        }
        state.onEscape = nil
    }

    deinit {
        // Must not touch actor-isolated state; teardown is a static function
        // over the locked state for exactly this reason (same Swift 6 shape
        // upstream settled on).
        shared.withLock { state in
            Self.teardown(&state)
        }
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system disabled the tap (timeout/user input): re-enable it
            // and let this pseudo-event through (upstream behavior).
            if let refcon {
                let lock = Unmanaged<KeyboardInputLock>.fromOpaque(refcon).takeUnretainedValue()
                lock.shared.withLock { state in
                    if let tap = state.tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let lock = Unmanaged<KeyboardInputLock>.fromOpaque(refcon).takeUnretainedValue()

        let rawType = type.rawValue
        let isMediaKey = rawType == KeyboardSwallow.systemDefinedType
            && NSEvent(cgEvent: event)?.subtype.rawValue == KeyboardSwallow.auxControlSubtype
        guard KeyboardSwallow.swallows(eventType: rawType, isMediaKeySubtype: isMediaKey) else {
            return Unmanaged.passUnretained(event)
        }

        if rawType == KeyboardSwallow.keyDownType,
           event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            let fired = lock.shared.withLock { state in
                state.escape.record(now: CACurrentMediaTime())
            }
            if fired {
                let onEscape = lock.shared.withLock { state in state.onEscape }
                if let onEscape {
                    DispatchQueue.main.async(execute: onEscape)
                }
            }
        }
        // nil swallows the event before it reaches any application.
        return nil
    }
}
