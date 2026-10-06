import AppKit
@testable import BlinkerApp
@testable import BlinkerCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class PermissionControllerTests: XCTestCase {
    private final class CaptureSource: WindowThumbnailCapturing {
        func prepare() async -> Bool {
            XCTFail("Checking permissions must not start window capture")
            return false
        }

        func capture(_: BrowserWindow) async -> CapturedWindowThumbnail? {
            XCTFail("Checking permissions must not capture a window")
            return nil
        }
    }

    private final class State {
        var accessibilityGranted = false
        var screenRecordingGranted = false
        var inputMonitoringGranted = false
        var accessibilityRequests = 0
        var screenRecordingRequests = 0
        var inputMonitoringRequests = 0
        var settingsOpenSucceeds = true
        var openedSettings: [AppPermission] = []
    }

    private struct Fixture {
        let state: State
        let thumbnails: WindowThumbnailStore
        let controller: PermissionController
    }

    private func fixture(granted: Bool = false) -> Fixture {
        let state = State()
        state.accessibilityGranted = granted
        state.screenRecordingGranted = granted
        state.inputMonitoringGranted = granted
        let thumbnails = WindowThumbnailStore(
            source: CaptureSource(), permissionCheck: { state.screenRecordingGranted }
        )
        let controller = PermissionController(
            thumbnails: thumbnails,
            accessibilityCheck: { state.accessibilityGranted },
            accessibilityRequest: { state.accessibilityRequests += 1 },
            screenRecordingRequest: { state.screenRecordingRequests += 1 },
            inputMonitoringCheck: { state.inputMonitoringGranted },
            inputMonitoringRequest: { state.inputMonitoringRequests += 1 },
            settingsOpener: {
                state.openedSettings.append($0)
                return state.settingsOpenSucceeds
            }
        )
        return Fixture(state: state, thumbnails: thumbnails, controller: controller)
    }

    func testInitializationAndRefreshNeverRequestPermissionsOrOpenSettings() {
        let fixture = fixture()
        fixture.controller.refresh()
        fixture.controller.refresh()
        XCTAssertEqual(fixture.state.accessibilityRequests, 0)
        XCTAssertEqual(fixture.state.screenRecordingRequests, 0)
        XCTAssertEqual(fixture.state.inputMonitoringRequests, 0)
        XCTAssertTrue(fixture.state.openedSettings.isEmpty)
        XCTAssertFalse(fixture.controller.accessibilityGranted)
        XCTAssertFalse(fixture.controller.screenRecordingGranted)
        XCTAssertFalse(fixture.controller.inputMonitoringGranted)
    }

    func testRepeatedExplicitRequestsPromptOnlyOnceAndDoNotAssumeApproval() {
        let fixture = fixture()
        for permission in AppPermission.allCases {
            fixture.controller.request(for: permission)
            fixture.controller.request(for: permission)
            XCTAssertFalse(fixture.controller.isGranted(permission))
        }
        XCTAssertEqual(fixture.state.accessibilityRequests, 1)
        XCTAssertEqual(fixture.state.screenRecordingRequests, 1)
        XCTAssertEqual(fixture.state.inputMonitoringRequests, 1)
        XCTAssertEqual(fixture.state.openedSettings, [
            .accessibility, .accessibility, .screenRecording, .screenRecording,
            .inputMonitoring, .inputMonitoring,
        ])
    }

    func testGrantAndRevocationFollowChecksAndTheSharedThumbnailStore() {
        let fixture = fixture()
        fixture.state.accessibilityGranted = true
        fixture.state.screenRecordingGranted = true
        fixture.controller.refresh()
        XCTAssertTrue(fixture.controller.accessibilityGranted)
        XCTAssertTrue(fixture.controller.screenRecordingGranted)

        fixture.state.screenRecordingGranted = false
        fixture.thumbnails.checkPermission()
        XCTAssertFalse(fixture.controller.screenRecordingGranted)
        fixture.state.accessibilityGranted = false
        fixture.controller.refresh()
        XCTAssertFalse(fixture.controller.accessibilityGranted)
        XCTAssertEqual(fixture.state.accessibilityRequests, 0)
        XCTAssertEqual(fixture.state.screenRecordingRequests, 0)
    }

    func testAlreadyGrantedRequestsOnlyOpenManagementSettings() {
        let fixture = fixture(granted: true)
        for permission in AppPermission.allCases {
            fixture.controller.request(for: permission)
            XCTAssertTrue(fixture.controller.isGranted(permission))
        }
        XCTAssertEqual(fixture.state.accessibilityRequests, 0)
        XCTAssertEqual(fixture.state.screenRecordingRequests, 0)
        XCTAssertEqual(fixture.state.openedSettings, AppPermission.allCases)
    }

    func testSettingsOpenFailureClearsAfterSuccessfulRetry() {
        let fixture = fixture()
        fixture.state.settingsOpenSucceeds = false
        XCTAssertFalse(fixture.controller.openSettings(for: .accessibility))
        XCTAssertTrue(fixture.controller.settingsOpenFailed)
        fixture.state.settingsOpenSucceeds = true
        XCTAssertTrue(fixture.controller.openSettings(for: .accessibility))
        XCTAssertFalse(fixture.controller.settingsOpenFailed)
        XCTAssertFalse(fixture.controller.accessibilityGranted)
    }

    func testDragProviderPreservesOriginalFileURLInsteadOfCopyingTheApp() async throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blinker permission fixture.app", isDirectory: true)
        let provider = DraggableAppIcon.itemProvider(for: appURL)
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier))
        let payload: Data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
        let serializedURL = try XCTUnwrap(String(data: payload, encoding: .utf8))
        XCTAssertEqual(URL(string: serializedURL), appURL)
    }
}
