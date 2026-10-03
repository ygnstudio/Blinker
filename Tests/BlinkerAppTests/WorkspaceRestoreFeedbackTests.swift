@testable import BlinkerApp
import Foundation
import XCTest

final class WorkspaceRestoreFeedbackTests: XCTestCase {
    func testZeroRestoresWithMissingPermissionExplainThePermissionFailure() {
        XCTAssertEqual(
            WorkspaceRestoreFeedback.message(count: 0, permissionGranted: false),
            String(localized: "需要辅助功能权限才能恢复窗口，请在「隐私与权限」中授权。")
        )
    }

    func testZeroRestoresWithPermissionDoNotClaimThereWereNoWindows() {
        XCTAssertEqual(
            WorkspaceRestoreFeedback.message(count: 0, permissionGranted: true),
            String(localized: "未能恢复任何窗口，请确认应用仍在运行，且窗口支持移动或调整大小。")
        )
    }

    func testSuccessfullyRestoredCountRemainsVisibleIfPermissionWasLaterLost() {
        XCTAssertEqual(
            WorkspaceRestoreFeedback.message(count: 2, permissionGranted: false),
            String(localized: "已恢复 \(2) 个窗口")
        )
    }
}
