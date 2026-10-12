import AppKit
import Carbon

/// Login and service launches start the menu-bar services without stealing focus.
/// A normal launch opens the workspace, or the existing first-run guide.
enum LaunchPresentationPolicy {
    enum Destination: Equatable {
        case background
        case onboarding
        case workbench
    }

    static func destination(hasSeenOnboarding: Bool, eventID: AEEventID?,
                            launchProperty: AEKeyword?) -> Destination {
        if eventID == kAEOpenApplication,
           launchProperty == keyAELaunchedAsLogInItem || launchProperty == keyAELaunchedAsServiceItem {
            return .background
        }
        return hasSeenOnboarding ? .workbench : .onboarding
    }

    @MainActor
    static func currentDestination(hasSeenOnboarding: Bool) -> Destination {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return destination(
            hasSeenOnboarding: hasSeenOnboarding,
            eventID: event?.eventID,
            launchProperty: event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        )
    }
}
