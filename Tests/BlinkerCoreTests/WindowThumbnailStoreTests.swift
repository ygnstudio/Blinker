import AppKit
@testable import BlinkerCore
import XCTest

@MainActor
final class WindowThumbnailStoreTests: XCTestCase {
    private final class Source: WindowThumbnailCapturing {
        var preparations = 0
        var available = true
        var imageAvailable = true
        var captured: [UUID] = []
        var beforePrepare: (() async -> Void)?
        var beforeCapture: (() async -> Void)?
        func prepare() async -> Bool {
            preparations += 1
            await beforePrepare?()
            return available
        }

        func capture(_ window: BrowserWindow) async -> CapturedWindowThumbnail? {
            captured.append(window.id)
            await beforeCapture?()
            guard imageAvailable else { return nil }
            return CapturedWindowThumbnail(image: NSImage(size: NSSize(width: 10, height: 10)), cost: 400)
        }
    }

    private func window(id: UUID = UUID(), minimized: Bool = false,
                        title: String = "Window", focusOrder: UInt64 = 0) -> BrowserWindow {
        BrowserWindow(id: id, pid: 42, appName: "App", title: title, bundleID: "app",
                      frame: CGRect(x: 0, y: 0, width: 800, height: 600), captureID: nil,
                      isMinimized: minimized, isHidden: false, isOnScreen: !minimized, focusOrder: focusOrder)
    }

    func testEquivalentRefreshKeepsAnInFlightCaptureIncludingMinimizedWindows() async throws {
        for minimized in [false, true] {
            let source = Source()
            let store = WindowThumbnailStore(source: source, permissionCheck: { true })
            let candidate = window(minimized: minimized)
            let capturing = expectation(description: "capture started")
            var resumeCapture: CheckedContinuation<Void, Never>?
            source.beforeCapture = {
                guard source.captured.count == 1 else { return }
                await withCheckedContinuation { continuation in
                    resumeCapture = continuation
                    capturing.fulfill()
                }
            }
            store.refresh([candidate], enabled: true, selected: candidate.id)
            let task = try XCTUnwrap(store.captureTask)
            await fulfillment(of: [capturing], timeout: 2)
            store.refresh([candidate], enabled: true, selected: candidate.id)
            let refocused = window(id: candidate.id, minimized: minimized, focusOrder: 1)
            store.refresh([refocused], enabled: true, selected: candidate.id)
            resumeCapture?.resume()
            await task.value

            XCTAssertNotNil(
                store.images[candidate.id],
                "An equivalent refresh must not discard a valid image"
            )
            XCTAssertEqual(source.captured, [candidate.id], "The same in-flight request should be shared")
            source.beforeCapture = nil
            store.stop()
            store.refresh([candidate], enabled: true, selected: candidate.id)
            await store.captureTask?.value
            XCTAssertNotNil(store.images[candidate.id])
            XCTAssertEqual(source.preparations, minimized ? 1 : 2,
                           "A cached minimized surface needs no new capture session")
        }
    }

    func testSupersededOffscreenCaptureDoesNotStartFailureCooldown() async throws {
        let source = Source()
        source.imageAvailable = false
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        let candidate = window(minimized: true)
        let capturing = expectation(description: "capture started")
        var resumeCapture: CheckedContinuation<Void, Never>?
        source.beforeCapture = {
            if source.captured.count == 1 {
                await withCheckedContinuation { continuation in
                    resumeCapture = continuation
                    capturing.fulfill()
                }
            } else {
                source.imageAvailable = true
            }
        }
        store.refresh([candidate], enabled: true, selected: candidate.id)
        let task = try XCTUnwrap(store.captureTask)
        await fulfillment(of: [capturing], timeout: 2)
        let updated = window(id: candidate.id, minimized: true, title: "Renamed")
        store.refresh([updated], enabled: true, selected: updated.id)
        resumeCapture?.resume()
        await task.value

        XCTAssertEqual(source.captured, [candidate.id, candidate.id])
        XCTAssertNotNil(store.images[candidate.id], "An obsolete attempt is not a current failure")
        source.beforeCapture = nil
    }

    func testTabSelectionChangeRejectsInFlightSurface() async throws {
        let source = Source()
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        var candidate = window()
        candidate.isTab = true
        candidate.isSelectedTab = true
        let capturing = expectation(description: "selected tab capture started")
        var resumeCapture: CheckedContinuation<Void, Never>?
        source.beforeCapture = {
            await withCheckedContinuation { continuation in
                resumeCapture = continuation
                capturing.fulfill()
            }
        }
        store.refresh([candidate], enabled: true, selected: candidate.id)
        let task = try XCTUnwrap(store.captureTask)
        await fulfillment(of: [capturing], timeout: 2)
        candidate.isSelectedTab = false
        store.refresh([candidate], enabled: true, selected: candidate.id)
        resumeCapture?.resume()
        await task.value

        XCTAssertTrue(store.images.isEmpty)
        XCTAssertFalse(store.captureUnavailable)
        XCTAssertEqual(source.captured, [candidate.id])
    }

    func testUnavailableServiceWaitsForOneExplicitRetry() async throws {
        let source = Source()
        source.available = false
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        var candidates = [window(), window()]
        var selected = candidates[1].id
        store.refresh(candidates, enabled: true, selected: selected)
        await store.captureTask?.value
        XCTAssertTrue(store.captureUnavailable)
        XCTAssertFalse(store.isRetrying)
        for _ in 0 ..< 3 {
            store.refresh(candidates, enabled: true, selected: selected)
            await store.captureTask?.value
        }
        XCTAssertEqual(source.preparations, 1)
        XCTAssertTrue(source.captured.isEmpty)
        candidates[1] = window()
        selected = candidates[1].id
        store.refresh(candidates, enabled: true, selected: selected)
        XCTAssertEqual(source.preparations, 1)

        source.available = true
        let retrying = expectation(description: "retry started")
        var resumeRetry: CheckedContinuation<Void, Never>?
        source.beforePrepare = {
            await withCheckedContinuation { continuation in
                resumeRetry = continuation
                retrying.fulfill()
            }
        }
        store.retry()
        let task = try XCTUnwrap(store.captureTask)
        await fulfillment(of: [retrying], timeout: 2)
        store.retry()
        store.refresh(candidates, enabled: true, selected: selected)
        XCTAssertTrue(store.captureUnavailable)
        XCTAssertTrue(store.isRetrying)
        resumeRetry?.resume()
        await task.value

        XCTAssertEqual(source.preparations, 2)
        XCTAssertEqual(source.captured, [selected, candidates[0].id])
        XCTAssertEqual(store.images.count, 2)
        XCTAssertFalse(store.captureUnavailable)
        XCTAssertFalse(store.isRetrying)
    }

    func testStopAndPermissionRevocationClearFailureAndCancelRetryPublication() async throws {
        let source = Source()
        source.available = false
        var granted = true
        let store = WindowThumbnailStore(source: source, permissionCheck: { granted })
        let candidate = window()
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        let retrying = expectation(description: "retry started")
        var resumeRetry: CheckedContinuation<Void, Never>?
        source.beforePrepare = {
            await withCheckedContinuation { continuation in
                resumeRetry = continuation
                retrying.fulfill()
            }
        }
        store.retry()
        let task = try XCTUnwrap(store.captureTask)
        await fulfillment(of: [retrying], timeout: 2)
        store.stop()
        resumeRetry?.resume()
        await task.value
        XCTAssertFalse(store.captureUnavailable)
        XCTAssertFalse(store.isRetrying)
        XCTAssertTrue(source.captured.isEmpty)

        source.beforePrepare = nil
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        XCTAssertTrue(store.captureUnavailable)
        let preparations = source.preparations
        granted = false
        store.retry()
        XCTAssertFalse(store.captureUnavailable)
        XCTAssertFalse(store.isRetrying)
        XCTAssertFalse(store.permissionGranted)
        XCTAssertEqual(source.preparations, preparations)
        XCTAssertNil(store.captureTask)
    }

    func testIndividualMissingImagesAreFallbacksAndOnlyOffscreenFailuresBackOff() async {
        let source = Source()
        source.imageAvailable = false
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        let active = window()
        let minimized = window(minimized: true)
        let candidates = [active, minimized]
        for _ in 0 ..< 2 {
            store.refresh(candidates, enabled: true, selected: active.id)
            await store.captureTask?.value
        }
        XCTAssertEqual(source.captured, [active.id, minimized.id, active.id])
        XCTAssertTrue(store.images.isEmpty)
        XCTAssertFalse(store.captureUnavailable)
        XCTAssertFalse(store.isRetrying)
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
        source.available = false
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        var candidate = window()
        candidate.isTab = true
        candidate.isSelectedTab = false
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        XCTAssertTrue(source.captured.isEmpty)
        XCTAssertTrue(store.images.isEmpty)
        XCTAssertEqual(source.preparations, 0)
        XCTAssertFalse(store.captureUnavailable)
    }
}

extension WindowThumbnailStoreTests {
    func testDepartureKeepsVisibleImagesButInvalidatesInFlightWorkImmediately() async throws {
        let source = Source()
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        let candidate = window()
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        let displayed = try XCTUnwrap(store.images[candidate.id])
        let capturing = expectation(description: "next capture started")
        var resumeCapture: CheckedContinuation<Void, Never>?
        source.beforeCapture = {
            await withCheckedContinuation { continuation in
                resumeCapture = continuation
                capturing.fulfill()
            }
        }
        store.refresh([candidate], enabled: true, selected: candidate.id)
        let task = try XCTUnwrap(store.captureTask)
        await fulfillment(of: [capturing], timeout: 2)
        store.stop(preservingPresentation: true)
        XCTAssertIdentical(store.images[candidate.id], displayed)
        resumeCapture?.resume()
        await task.value
        XCTAssertIdentical(
            store.images[candidate.id],
            displayed,
            "Departure must not accept a late new image"
        )
        store.stop()
        XCTAssertTrue(store.images.isEmpty)
    }

    func testDepartureRetainsFailureLayoutButCannotRetryCancelledRequest() async {
        let source = Source()
        source.available = false
        let store = WindowThumbnailStore(source: source, permissionCheck: { true })
        let candidate = window()
        store.refresh([candidate], enabled: true, selected: candidate.id)
        await store.captureTask?.value
        store.stop(preservingPresentation: true)
        XCTAssertTrue(store.captureUnavailable)
        store.retry()
        XCTAssertNil(store.captureTask)
        XCTAssertEqual(source.preparations, 1)
        store.stop()
        XCTAssertFalse(store.captureUnavailable)
    }
}
