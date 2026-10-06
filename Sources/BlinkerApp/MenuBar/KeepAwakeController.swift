import Foundation
import IOKit.pwr_mgt

/// Keep-awake toggle for the quick actions block. An active toggle holds a
/// PreventUserIdleSystemSleep power assertion: the system never idles into
/// sleep while the display may still turn off on its own schedule, and
/// lid-close behavior stays untouched. No permission is required. The
/// assertion dies with the process, so quitting Blinker always hands sleep
/// behavior back to the system.
///
/// The controller is owned by the presentation layer for the app's
/// lifetime: the panel's hosting controller is recreated on every open, so
/// a panel-scoped owner would leak its assertion when the panel closes.
@MainActor
final class KeepAwakeController: ObservableObject {
    @Published private(set) var isActive = false

    /// Injectable so tests never touch power management — an assertion
    /// created there would keep the test host awake past its own checks.
    private let create: () -> IOPMAssertionID?
    private let release: (IOPMAssertionID) -> Void
    private var assertionID: IOPMAssertionID?

    init(create: @escaping () -> IOPMAssertionID? = KeepAwakeController.createAssertion,
         release: @escaping (IOPMAssertionID) -> Void = KeepAwakeController.releaseAssertion) {
        self.create = create
        self.release = release
    }

    func setActive(_ active: Bool) {
        if active {
            start()
        } else {
            stop()
        }
    }

    /// Starting is idempotent; a failed creation leaves the toggle off so
    /// the UI never claims a hold the system does not have.
    private func start() {
        guard assertionID == nil else { return }
        assertionID = create()
        isActive = assertionID != nil
    }

    private func stop() {
        guard let assertionID else { return }
        self.assertionID = nil
        isActive = false
        release(assertionID)
    }

    private nonisolated static func createAssertion() -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            "Blinker Keep Awake" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            &assertionID
        )
        return status == kIOReturnSuccess ? assertionID : nil
    }

    private nonisolated static func releaseAssertion(_ assertionID: IOPMAssertionID) {
        IOPMAssertionRelease(assertionID)
    }
}
