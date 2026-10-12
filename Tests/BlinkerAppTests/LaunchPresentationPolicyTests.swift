import Carbon
@testable import BlinkerApp
import XCTest

final class LaunchPresentationPolicyTests: XCTestCase {
    func testManualLaunchAfterOnboardingOpensWorkbench() {
        XCTAssertEqual(destination(seen: true), .workbench)
        XCTAssertEqual(destination(seen: true, eventID: kAEOpenApplication), .workbench)
    }

    func testFirstManualLaunchKeepsExistingOnboarding() {
        XCTAssertEqual(destination(seen: false), .onboarding)
        XCTAssertEqual(destination(seen: false, eventID: kAEOpenApplication), .onboarding)
    }

    func testLoginAndServiceLaunchesStayInBackgroundEvenBeforeOnboarding() {
        for seen in [false, true] {
            for property in [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem] {
                XCTAssertEqual(destination(seen: seen, eventID: kAEOpenApplication,
                                           property: property), .background)
            }
        }
    }

    func testUnrelatedEventDoesNotTurnManualLaunchIntoBackgroundLaunch() {
        XCTAssertEqual(destination(seen: true, eventID: kAEReopenApplication,
                                   property: keyAELaunchedAsLogInItem), .workbench)
        XCTAssertEqual(destination(seen: false, eventID: kAEReopenApplication,
                                   property: keyAELaunchedAsServiceItem), .onboarding)
    }

    func testMissingOrUnknownLaunchPropertyUsesManualPresentation() {
        XCTAssertEqual(destination(seen: true, eventID: kAEOpenApplication, property: 0), .workbench)
        XCTAssertEqual(destination(seen: false, eventID: kAEOpenApplication, property: 0), .onboarding)
    }

    private func destination(seen: Bool, eventID: AEEventID? = nil,
                             property: AEKeyword? = nil) -> LaunchPresentationPolicy.Destination {
        LaunchPresentationPolicy.destination(hasSeenOnboarding: seen,
                                             eventID: eventID, launchProperty: property)
    }
}
