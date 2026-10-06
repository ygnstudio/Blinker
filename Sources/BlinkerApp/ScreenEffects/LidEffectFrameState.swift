import CoreVideo
import Foundation

/// One replaceable input frame, shared by the capture queue and the main-thread
/// renderer. A stopped receiver is terminal, so an old stream cannot revive it.
final class LidEffectFrameState: @unchecked Sendable {
    private enum Phase { case ready, running, failed, stopped }
    private let lock = NSLock()
    private var phase = Phase.ready
    private var generation = UUID()
    private var latest: CVPixelBuffer?
    private var streamID: ObjectIdentifier?
    private var presented = false
    private var drawQueued = false
    private var settlement: UUID?
    private var settled = false

    func start() -> Bool {
        lock.withLock {
            guard phase == .ready || phase == .running else { return false }
            phase = .running
            return true
        }
    }

    func accept(_ buffer: CVPixelBuffer, stream: ObjectIdentifier) {
        lock.withLock {
            guard phase == .ready || phase == .running else { return }
            guard streamID == nil || streamID == stream else { return }
            streamID = stream
            latest = buffer
        }
    }

    func frame() -> (buffer: CVPixelBuffer, generation: UUID)? {
        lock.withLock {
            guard phase == .running, let latest else { return nil }
            return (latest, generation)
        }
    }

    func requestDraw() -> Bool {
        lock.withLock {
            guard phase == .running, !drawQueued else { return false }
            drawQueued = true
            return true
        }
    }

    func finishDraw() {
        lock.withLock { drawQueued = false }
    }

    func markPresented(_ ticket: UUID) -> Bool {
        lock.withLock {
            guard phase == .running, generation == ticket, !presented else { return false }
            presented = true
            return true
        }
    }

    /// Repeated zero targets keep one ending. New input invalidates any queued
    /// zero-frame completion before that completion can close the reused overlay.
    func setTarget(isZero: Bool, beginsNewMotion: Bool = false) {
        lock.withLock {
            guard phase == .ready || phase == .running else { return }
            if !isZero {
                settlement = nil
                settled = false
            } else if beginsNewMotion || settlement == nil {
                settlement = UUID()
                settled = false
            }
        }
    }

    func settlementTicket(renderedProgress: Double) -> UUID? {
        lock.withLock {
            guard phase == .running, renderedProgress == 0, !settled else { return nil }
            return settlement
        }
    }

    func markSettled(_ ticket: UUID, generation frameGeneration: UUID) -> Bool {
        lock.withLock {
            guard phase == .running, generation == frameGeneration,
                  settlement == ticket, !settled else { return false }
            settled = true
            return true
        }
    }

    func fail(stream: ObjectIdentifier? = nil, ticket: UUID? = nil) -> UUID? {
        lock.withLock {
            guard phase == .ready || phase == .running else { return nil }
            if let stream, let streamID, stream != streamID {
                return nil
            }
            if let ticket, ticket != generation {
                return nil
            }
            phase = .failed
            latest = nil
            return generation
        }
    }

    func isFailureCurrent(_ ticket: UUID) -> Bool {
        lock.withLock { phase == .failed && generation == ticket }
    }

    func stop() {
        lock.withLock {
            phase = .stopped
            generation = UUID()
            latest = nil
            drawQueued = false
            settlement = nil
        }
    }
}

/// Positive targets follow elapsed time. A normal ending reaches exact zero in
/// finite time; explicit reset is reserved for cancellation or invalid input.
struct LidEffectMotion {
    private struct Ending {
        let start: Double
        let duration: TimeInterval
        var elapsed: TimeInterval = 0
    }

    private(set) var progress: Double
    private var hasInitialFrame: Bool
    private var ending: Ending?

    init(progress: Double = 0) {
        self.progress = LidEffectProcessor.unit(progress)
        hasInitialFrame = self.progress > 0
    }

    mutating func beginOpening(at initialProgress: Double) {
        guard initialProgress.isFinite, initialProgress > 0 else { return }
        ending = nil
        // A reused overlay continues from its visible strength. A new/settled
        // renderer presents the observed opening strength for its first frame.
        if progress == 0 {
            progress = LidEffectProcessor.unit(initialProgress)
            hasInitialFrame = true
        }
    }

    mutating func cancelEnding() {
        ending = nil
    }

    mutating func reset() {
        progress = 0
        hasInitialFrame = false
        ending = nil
    }

    mutating func advance(to target: Double, elapsed: TimeInterval, frames: Int,
                          speed: Double = 1) -> Double {
        guard target.isFinite else { reset(); return 0 }
        let target = LidEffectProcessor.unit(target)
        if hasInitialFrame {
            hasInitialFrame = false
            return progress
        }
        let speed = speed.isFinite ? min(2, max(0.25, speed)) : 1
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        if target == 0 {
            return finish(elapsed: elapsed, frames: frames, speed: speed)
        }
        ending = nil
        guard frames > 1 || speed < 1 else { progress = target; return progress }
        let blend = 1 - exp(-min(0.1, elapsed) * 60 * speed / Double(min(30, max(1, frames))))
        progress += (target - progress) * blend
        return progress
    }

    private mutating func finish(elapsed: TimeInterval, frames: Int, speed: Double) -> Double {
        guard progress > 0 else { ending = nil; return 0 }
        // The tail is what reads as "the animation": too short and the effect
        // is gone before the lid finishes opening. ~1.07 s at 100 % speed.
        let duration = min(2, max(0.12, Double(min(30, max(1, frames))) / (15 * speed)))
        var transition = ending ?? Ending(start: progress, duration: duration)
        transition.elapsed = min(transition.duration, transition.elapsed + elapsed)
        if transition.duration - transition.elapsed < 0.000000001 {
            progress = 0
            ending = nil
        } else {
            let remaining = 1 - transition.elapsed / transition.duration
            progress = transition.start * remaining * remaining * remaining
            ending = transition
        }
        return progress
    }
}
