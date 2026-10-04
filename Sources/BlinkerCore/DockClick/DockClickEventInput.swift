import CoreGraphics
import Foundation

/// Normalize the event's geometry and modifiers alongside its local receipt time.
/// The caller supplies uptime so input processing and delayed admission use one clock.
struct DockClickEventInput {
    let point: CGPoint
    let receivedAt: TimeInterval
    let isPlain: Bool
    let isSingle: Bool

    init(_ event: CGEvent, receivedAt: TimeInterval) {
        point = event.location
        // Event producers can supply another epoch (including synthesized input).
        // Never compare CGEvent.timestamp with this process's systemUptime.
        self.receivedAt = receivedAt
        isPlain = event.flags.isDisjoint(with: [.maskCommand, .maskAlternate, .maskControl,
                                                .maskShift, .maskSecondaryFn])
        isSingle = event.getIntegerValueField(.mouseEventClickState) == 1
    }
}
