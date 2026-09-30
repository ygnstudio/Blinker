import Foundation

/// A stable target must remain under the cursor until the appearance delay
/// expires. Dwell protection starts separately, after the panel becomes visible.
struct OverlayWakeGate {
    private var target: String?
    private var beganAt: TimeInterval = 0

    mutating func remaining(for target: String, now: TimeInterval, delayMilliseconds: Int) -> TimeInterval {
        if self.target != target {
            self.target = target
            beganAt = now
        }
        return max(0, Double(delayMilliseconds) / 1000 - (now - beganAt))
    }

    mutating func reset() {
        target = nil
    }
}
