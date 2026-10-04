import Foundation

/// Window animations may finish after a successful request has returned.
/// Confirm the postcondition without issuing the mutation a second time.
enum WindowMinimizationConfirmation {
    static let timeout: TimeInterval = 3.5
    static let interval: TimeInterval = 0.02
    static let maximumReads = 176

    struct Deadline {
        let time: TimeInterval
        let now: () -> TimeInterval

        init(time: TimeInterval? = nil,
             now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            self.now = now
            self.time = time ?? now() + timeout
        }

        var remaining: TimeInterval {
            time - now()
        }
    }

    /// Only the serial AX worker uses the blocking variant.
    static func confirm(expected: Bool, reads: [(TimeInterval) -> Bool?],
                        deadline: Deadline = .init(),
                        wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> Set<Int> {
        var confirmed = Set<Int>()
        for attempt in 0 ..< maximumReads {
            for index in reads.indices where !confirmed.contains(index) {
                let remaining = deadline.remaining
                guard remaining > 0 else { return confirmed }
                if reads[index](min(0.04, remaining)) == expected {
                    confirmed.insert(index)
                }
            }
            let remaining = deadline.remaining
            guard confirmed.count < reads.count, remaining > 0, attempt + 1 < maximumReads else { break }
            wait(min(interval, remaining))
        }
        return confirmed
    }

    struct NativeResult {
        var confirmed: Set<Int> = []
        var pending: Set<Int>
    }

    /// All native windows share one deadline; waiting yields the main actor.
    /// A nil read means that the window was closed or its identity no longer matches.
    @MainActor
    static func native(expected: Bool, reads: [() -> Bool?], isCurrent: () -> Bool,
                       deadline: Deadline = .init(),
                       wait: (TimeInterval) async -> Void = {
                           try? await Task.sleep(for: .seconds($0))
                       }) async -> NativeResult {
        var result = NativeResult(pending: Set(reads.indices))
        for attempt in 0 ..< maximumReads {
            guard isCurrent(), deadline.remaining > 0 else { return result }
            for index in result.pending {
                guard let actual = reads[index]() else {
                    result.pending.remove(index)
                    continue
                }
                if actual == expected {
                    result.confirmed.insert(index)
                    result.pending.remove(index)
                }
            }
            let remaining = deadline.remaining
            guard !result.pending.isEmpty, remaining > 0, attempt + 1 < maximumReads else { break }
            await wait(min(interval, remaining))
        }
        return result
    }
}
