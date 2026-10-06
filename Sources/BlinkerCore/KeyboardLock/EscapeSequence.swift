import Foundation

/// Counts repeated Escape presses inside a sliding time window — the
/// emergency exit from keyboard cleaning (three presses, the convention in
/// upstream cleaners) and the plain exit from display cleaning (one press).
public struct EscapeSequence {
    public let threshold: Int
    public let window: TimeInterval
    private var presses: [TimeInterval] = []

    public init(threshold: Int, window: TimeInterval) {
        self.threshold = max(1, threshold)
        self.window = window
    }

    /// Records a press; returns true once `threshold` presses land inside the
    /// window, then resets so a later sequence can fire again.
    public mutating func record(now: TimeInterval) -> Bool {
        presses = presses.filter { now - $0 <= window }
        presses.append(now)
        guard presses.count >= threshold else { return false }
        presses.removeAll()
        return true
    }
}
