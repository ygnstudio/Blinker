import Combine
import Foundation

/// Duo is opt-in. Values are bounded before rendering or persistence.
struct LidEffectConfiguration: Codable, Equatable {
    var isEnabled = false
    var referenceAngle = 110.0
    var sensitivity = 6.0
    var fullEffectSpan = 45.0
    var clearDelay = 0.6
    var holdsUntilReopened = false
    var tilt = 60.0
    var frost = 0.72
    var darkness = 0.21
    var blur = 0.41
    var edgeSoftness = 0.75
    var smoothingFrames = 16
    var animationSpeed = 1.0

    private enum CodingKeys: String, CodingKey {
        case isEnabled, referenceAngle, sensitivity, fullEffectSpan, clearDelay, holdsUntilReopened
        case tilt, frost, darkness, blur, edgeSoftness, smoothingFrames, animationSpeed
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        referenceAngle = try values.decode(Double.self, forKey: .referenceAngle)
        sensitivity = try values.decode(Double.self, forKey: .sensitivity)
        fullEffectSpan = try values.decode(Double.self, forKey: .fullEffectSpan)
        clearDelay = try values.decode(Double.self, forKey: .clearDelay)
        holdsUntilReopened = try values.decode(Bool.self, forKey: .holdsUntilReopened)
        tilt = try values.decode(Double.self, forKey: .tilt)
        frost = try values.decode(Double.self, forKey: .frost)
        darkness = try values.decode(Double.self, forKey: .darkness)
        blur = try values.decode(Double.self, forKey: .blur)
        edgeSoftness = try values.decode(Double.self, forKey: .edgeSoftness)
        smoothingFrames = try values.decode(Int.self, forKey: .smoothingFrames)
        // Existing v1 archives retain every saved choice and their original transition speed.
        animationSpeed = try values.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? 1
    }

    func normalized() -> Self {
        var result = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.referenceAngle = clamp(referenceAngle, 20 ... 180, fallback: 110)
        // The sensor reports whole degrees; a one-step change must not start a gesture.
        result.sensitivity = clamp(sensitivity, 3 ... 15, fallback: 6)
        result.fullEffectSpan = clamp(fullEffectSpan, 5 ... 90, fallback: 45)
        result.clearDelay = clamp(clearDelay, 0 ... 5, fallback: 0.6)
        result.tilt = clamp(tilt, 0 ... 80, fallback: 60)
        result.frost = clamp(frost, 0 ... 1, fallback: 0.72)
        result.darkness = clamp(darkness, 0 ... 1, fallback: 0.21)
        result.blur = clamp(blur, 0 ... 1, fallback: 0.41)
        result.edgeSoftness = clamp(edgeSoftness, 0 ... 1, fallback: 0.75)
        result.smoothingFrames = min(30, max(1, smoothingFrames))
        result.animationSpeed = clamp(animationSpeed, 0.25 ... 2, fallback: 1)
        return result
    }
}

@MainActor
final class LidEffectPreferences: ObservableObject {
    static let shared = LidEffectPreferences()
    static let key = "lidEffects.v1"
    @Published private(set) var configuration: LidEffectConfiguration
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(LidEffectConfiguration.self, from: $0) }?
            .normalized() ?? .init()
    }

    func update(_ change: (inout LidEffectConfiguration) -> Void) {
        var value = configuration
        change(&value)
        value = value.normalized()
        guard value != configuration, let data = try? JSONEncoder().encode(value) else { return }
        configuration = value
        defaults.set(data, forKey: Self.key)
    }

    func reset() {
        update { $0 = .init() }
    }

    func applyRecommended() {
        let enabled = configuration.isEnabled
        let referenceAngle = configuration.referenceAngle
        update {
            $0 = .init()
            $0.isEnabled = enabled
            $0.referenceAngle = referenceAngle
        }
    }
}
