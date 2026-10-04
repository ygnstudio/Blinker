import Foundation

/// Motion is tracked independently of visual strength. A zero-strength frame or
/// an interrupted candidate never requires the user to stop before moving again.
struct LidEffectGesture {
    private enum Direction: Double {
        case closing = -1
        case opening = 1

        var reversed: Self {
            self == .closing ? .opening : .closing
        }

        func distance(from start: Double, to end: Double) -> Double {
            (end - start) * rawValue
        }
    }

    private struct Reading {
        let angle: Double
        let time: TimeInterval
    }

    private struct Candidate {
        let direction: Direction
        let anchor: Double
        let since: TimeInterval
        let recoveryOrigin: Double?
        let startedWhileVisible: Bool
        var extreme: Double
        var maximumProgress: Double
        var hasLeftEffectRange: Bool
        var qualifyingReadings = 0
        var confirmed = false
    }

    private struct Activity {
        let direction: Direction
        var extreme: Double
        var reverseExtreme: Double
        var lastMovement: TimeInterval

        mutating func observe(angle: Double, time: TimeInterval) {
            if direction.distance(from: extreme, to: angle) > 0 {
                extreme = angle
                reverseExtreme = angle
                lastMovement = time
            } else if direction.reversed.distance(from: reverseExtreme, to: angle) > 0 {
                // Slow reversal is movement too. A bounded wobble only expands
                // this range once; repeated back-and-forth cannot renew it.
                reverseExtreme = angle
                lastMovement = time
            }
        }
    }

    private static let confirmationDuration = 0.15
    private static let stopDetectionDuration = 0.3
    private static let directionNoise = 0.5
    private var previousReading: Reading?
    private var candidate: Candidate?
    private var activity: Activity?
    private var allowsVisualTarget = false
    private var lastTime: TimeInterval?
    private(set) var openingStartProgress: Double?

    mutating func update(angle: Double?, time: TimeInterval,
                         configuration: LidEffectConfiguration, isFreshReading: Bool = true) -> Double {
        openingStartProgress = nil
        guard configuration.isEnabled, let angle, angle.isFinite, (0 ... 360).contains(angle),
              time.isFinite else { reset(); return 0 }
        if let lastTime, time < lastTime {
            reset()
        }
        lastTime = time
        let configuration = configuration.normalized()
        let progress = Self.progress(for: angle, configuration: configuration)
        if isFreshReading {
            observe(.init(angle: angle, time: time), progress: progress, configuration: configuration)
        }
        if let activity, !configuration.holdsUntilReopened,
           time - activity.lastMovement >= max(Self.stopDetectionDuration, configuration.clearDelay) {
            self.activity = nil
            candidate = nil
            allowsVisualTarget = false
        }
        if progress <= 0 {
            allowsVisualTarget = false
        }
        return activity != nil && allowsVisualTarget ? progress : 0
    }

    private mutating func observe(_ reading: Reading, progress: Double,
                                  configuration: LidEffectConfiguration) {
        defer { previousReading = reading }
        guard let previousReading else { return }
        activity?.observe(angle: reading.angle, time: reading.time)
        if let candidate {
            advance(candidate, reading: reading, progress: progress, configuration: configuration)
        } else if reading.angle != previousReading.angle {
            self.candidate = makeCandidate(from: previousReading.angle, reading: reading,
                                           configuration: configuration, recoveryOrigin: nil)
        }
        confirmIfReady(reading: reading, progress: progress, threshold: configuration.sensitivity)
    }

    private mutating func advance(_ previous: Candidate, reading: Reading, progress: Double,
                                  configuration: LidEffectConfiguration) {
        if !previous.confirmed, let origin = previous.recoveryOrigin,
           previous.direction.distance(from: previous.anchor, to: origin) > 0,
           previous.direction.distance(from: origin, to: reading.angle) >= 0 {
            // A one-sample excursion returning to its original baseline is not
            // a second, opposite gesture whose peak can seed an animation.
            restartBeyondOrigin(origin, reading: reading, configuration: configuration)
            return
        }
        let reversed = previous.direction.distance(from: reading.angle, to: previous.extreme)
            >= Self.directionNoise
        if reversed {
            let origin = previous.confirmed ? nil : previous.recoveryOrigin ?? previous.anchor
            if !previous.confirmed,
               previous.direction.distance(from: previous.anchor, to: reading.angle) <= 0 {
                restartBeyondOrigin(previous.recoveryOrigin ?? previous.anchor,
                                    reading: reading, configuration: configuration)
            } else {
                candidate = makeCandidate(from: previous.extreme, reading: reading,
                                          configuration: configuration, recoveryOrigin: origin)
            }
            return
        }
        var next = previous
        if next.direction.distance(from: next.extreme, to: reading.angle) > 0 {
            next.extreme = reading.angle
        }
        next.maximumProgress = max(next.maximumProgress, progress)
        next.hasLeftEffectRange = next.hasLeftEffectRange || progress <= 0
        candidate = next
    }

    private mutating func restartBeyondOrigin(_ origin: Double, reading: Reading,
                                              configuration: LidEffectConfiguration) {
        // Returning exactly to the baseline cancels a spike. Continuing beyond
        // it is fresh motion: keep its first sample and use the pre-spike origin
        // for distance and opening strength, never the rejected excursion peak.
        candidate = reading.angle == origin ? nil : makeCandidate(from: origin, reading: reading,
                                                                  configuration: configuration,
                                                                  recoveryOrigin: nil)
    }

    private func makeCandidate(from anchor: Double, reading: Reading,
                               configuration: LidEffectConfiguration, recoveryOrigin: Double?) -> Candidate {
        let direction: Direction = reading.angle > anchor ? .opening : .closing
        let progress = Self.progress(for: reading.angle, configuration: configuration)
        return Candidate(direction: direction, anchor: anchor, since: reading.time,
                         recoveryOrigin: recoveryOrigin, startedWhileVisible: allowsVisualTarget,
                         extreme: reading.angle,
                         maximumProgress: max(
                             Self.progress(for: anchor, configuration: configuration),
                             progress
                         ),
                         hasLeftEffectRange: progress <= 0)
    }

    private mutating func confirmIfReady(reading: Reading, progress: Double, threshold: Double) {
        guard var candidate else { return }
        let excursion = candidate.direction.distance(from: candidate.anchor, to: reading.angle)
        candidate.qualifyingReadings = excursion >= threshold ? min(2, candidate.qualifyingReadings + 1) : 0
        let ready = candidate.qualifyingReadings >= 2
            && reading.time - candidate.since >= Self.confirmationDuration
        if !candidate.confirmed, ready {
            if candidate.direction == .opening, !candidate.startedWhileVisible,
               candidate.maximumProgress > 0 {
                openingStartProgress = candidate.maximumProgress
            }
            candidate.confirmed = true
            activity = .init(direction: candidate.direction, extreme: reading.angle,
                             reverseExtreme: reading.angle, lastMovement: reading.time)
        }
        if candidate.confirmed,
           candidate.direction == .closing || !candidate.hasLeftEffectRange {
            allowsVisualTarget = progress > 0
        }
        self.candidate = candidate
    }

    private static func progress(for angle: Double, configuration: LidEffectConfiguration) -> Double {
        min(
            1,
            max(
                0,
                (configuration.referenceAngle - angle - configuration.sensitivity) / configuration
                    .fullEffectSpan
            )
        )
    }

    mutating func reset() {
        previousReading = nil
        candidate = nil
        activity = nil
        allowsVisualTarget = false
        lastTime = nil
        openingStartProgress = nil
    }
}
