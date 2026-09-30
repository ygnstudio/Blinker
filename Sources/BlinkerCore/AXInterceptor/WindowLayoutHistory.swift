import CoreGraphics

/// Bounded, per-window history. The performer serializes access. Failed writes
/// never enter history; window identity is independent of its current frame.
struct WindowLayoutHistory<Key: Hashable> {
    struct Entry {
        let action: ButtonAction
        let before: CGRect
        let after: CGRect
    }

    private var entries: [Key: [Entry]] = [:]
    private var order: [Key] = []

    func previousFrame(for key: Key) -> CGRect? {
        entries[key]?.last?.before
    }

    func toggleFrame(for key: Key, action: ButtonAction, current: CGRect) -> CGRect? {
        guard action == .maximize || action == .almostMaximize,
              let last = entries[key]?.last, last.action == action,
              Self.matches(current, last.after) else { return nil }
        return last.before
    }

    mutating func record(key: Key, action: ButtonAction, before: CGRect, after: CGRect) {
        guard !Self.matches(before, after) else { return }
        var history = entries[key] ?? []
        history.append(Entry(action: action, before: before, after: after))
        entries[key] = Array(history.suffix(10))
        order.removeAll { $0 == key }
        order.append(key)
        if order.count > 128 {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func didRestore(_ key: Key) {
        _ = entries[key]?.popLast()
        if entries[key]?.isEmpty == true {
            entries.removeValue(forKey: key)
            order.removeAll { $0 == key }
        }
    }

    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }
}
