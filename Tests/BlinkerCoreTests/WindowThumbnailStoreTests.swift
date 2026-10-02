import AppKit
@testable import BlinkerCore
import XCTest

@MainActor
final class WindowThumbnailStoreTests: XCTestCase {
    private final class Source: WindowThumbnailCapturing {
        var captured: [UUID] = []
        func prepare() async -> Bool {
            true
        }

        func capture(_ window: BrowserWindow) async -> CapturedWindowThumbnail? {
            captured.append(window.id)
            return CapturedWindowThumbnail(image: NSImage(size: NSSize(width: 10, height: 10)), cost: 400)
        }
    }

    private func window() -> BrowserWindow {
        BrowserWindow(id: UUID(), pid: 42, appName: "App", title: "Window", bundleID: "app",
                      frame: CGRect(x: 0, y: 0, width: 800, height: 600), captureID: nil,
                      isMinimized: false, isHidden: false, isOnScreen: true, focusOrder: 0)
    }

    func testStopDuringFinalValidationDoesNotRepublishOrCacheOldImage() async throws {
        let source = Source()
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        let candidate = window()
        let validating = expectation(description: "post-capture validation started")
        var resumeValidation: CheckedContinuation<Bool, Never>?
        var validations = 0
        store.canCapture = { _ in
            validations += 1
            guard validations == 2 else { return true }
            return await withCheckedContinuation { continuation in
                resumeValidation = continuation
                validating.fulfill()
            }
        }
        store.refresh([candidate], enabled: true, selected: candidate.id)
        let task = try XCTUnwrap(store.captureTask)
        await fulfillment(of: [validating], timeout: 2)
        store.stop()
        resumeValidation?.resume(returning: true)
        await task.value
        XCTAssertTrue(store.images.isEmpty)
        store.refresh([candidate], enabled: true, selected: candidate.id)
        XCTAssertTrue(store.images.isEmpty, "stale capture must not enter the cache")
        await store.captureTask?.value
        XCTAssertEqual(store.images.count, 1)
    }

    func testCaptureDeduplicatesAndBoundsBatchWhilePrioritizingSelection() async {
        let source = Source()
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        let candidates = (0 ..< 40).map { _ in window() }
        let selected = candidates[39]
        store.refresh(candidates + candidates, enabled: true, selected: selected.id)
        await store.captureTask?.value
        XCTAssertEqual(source.captured.count, 32)
        XCTAssertEqual(Set(source.captured).count, 32)
        XCTAssertEqual(source.captured.first, selected.id)
        XCTAssertEqual(store.images.count, 32)
        store.refresh(candidates, enabled: false, selected: selected.id)
        XCTAssertTrue(store.images.isEmpty)
    }

    func testPermissionRevocationClearsCachedImages() async {
        let source = Source()
        var granted = true
        let store = WindowThumbnailStore(source: source, permissionCheck: { granted })
        let candidate = window()
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        XCTAssertEqual(store.images.count, 1)
        granted = false
        store.checkPermission()
        XCTAssertFalse(store.permissionGranted)
        XCTAssertTrue(store.images.isEmpty)
        granted = true
        store.refresh([candidate], enabled: true, selected: candidate.id)
        XCTAssertTrue(store.images.isEmpty)
        await store.captureTask?.value
    }

    func testInactiveTabsNeverCaptureAnotherTabsSurface() async {
        let source = Source()
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        var candidate = window()
        candidate.isTab = true
        candidate.isSelectedTab = false
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        XCTAssertTrue(source.captured.isEmpty)
        XCTAssertTrue(store.images.isEmpty)
    }
}
