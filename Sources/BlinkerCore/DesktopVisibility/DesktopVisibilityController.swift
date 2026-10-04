import Combine

/// Show Desktop minimizes only this Space's ordinary windows. A subsequent
/// toggle restores this controller's verified batch, never pre-minimized windows.
@MainActor
public final class DesktopVisibilityController: ObservableObject {
    @Published public private(set) var isDesktopShown = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastFailureCount = 0
    private let session: WindowVisibilitySession

    public convenience init(service: WindowMinimizationService? = nil) {
        self.init(session: WindowVisibilitySession(service: service))
    }

    init(session: WindowVisibilitySession) {
        self.session = session
        session.$hasMinimizedWindows.assign(to: &$isDesktopShown)
        session.$isBusy.assign(to: &$isBusy)
        session.$lastFailureCount.assign(to: &$lastFailureCount)
    }

    @discardableResult
    public func toggle() -> Bool {
        isDesktopShown ? session.restore(activateOriginal: true) : session.minimize()
    }

    public func setPaused(_ value: Bool) {
        session.setPaused(value)
    }

    public func stop() {
        session.stop()
    }
}
