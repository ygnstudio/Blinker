import Foundation

/// Modifier state and deferred commits belong to one presentation, including while its catalog loads.
public struct WindowBrowserKeyboardSession {
    public private(set) var id = UUID()
    public private(set) var isHoldingOption = false
    private var isOpen = false
    private var pendingCommit = false

    public init() {}

    public mutating func begin(holdingOption: Bool) {
        id = UUID()
        isOpen = true
        isHoldingOption = holdingOption
        pendingCommit = false
    }

    public mutating func dismiss() {
        id = UUID()
        isOpen = false
        isHoldingOption = false
        pendingCommit = false
    }

    /// Returns whether this release ends an active keyboard selection.
    public mutating func releaseOption() -> Bool {
        guard isOpen, isHoldingOption else { return false }
        isHoldingOption = false
        return true
    }

    public mutating func deferCommitUntilLoaded() {
        guard isOpen else { return }
        pendingCommit = true
    }

    /// Late refreshes from dismissed or replaced presentations cannot consume a newer pending commit.
    public mutating func takePendingCommit(for presentation: UUID) -> Bool {
        guard isOpen, id == presentation, pendingCommit else { return false }
        pendingCommit = false
        return true
    }
}
