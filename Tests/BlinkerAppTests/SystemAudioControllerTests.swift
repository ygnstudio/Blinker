@testable import BlinkerApp
import Combine
import CoreAudio
import XCTest

@MainActor
final class SystemAudioControllerTests: XCTestCase {
    private final class Backend: SystemAudioOperating {
        var onChange: (@MainActor @Sendable () -> Void)?
        var requests: [SystemAudioRequest] = []
        var tokens: [SystemAudioCancellation] = []
        var completions: [@MainActor @Sendable (SystemAudioResult) -> Void] = []
        var stops = 0
        func perform(_ request: SystemAudioRequest, cancellation: SystemAudioCancellation,
                     completion: @escaping @MainActor @Sendable (SystemAudioResult) -> Void) {
            requests.append(request)
            tokens.append(cancellation)
            completions.append(completion)
        }

        func stop() {
            stops += 1
        }

        func complete(_ state: SystemAudioState, error: SystemAudioFailure? = nil) {
            completions.removeFirst()(.init(state: state, error: error))
        }
    }

    private let first = SystemAudioOutput(id: 10, uid: "first", name: "First", isBluetooth: false)
    private let second = SystemAudioOutput(id: 20, uid: "second", name: "Second", isBluetooth: true)
    private var state: SystemAudioState {
        .init(outputs: [first, second], currentDeviceID: first.id, volume: 0.5,
              isMuted: false, canSetVolume: true, canMute: true)
    }

    func testStartStopAreIdempotentAndNeverWrite() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        XCTAssertTrue(backend.requests.isEmpty)
        controller.setVolume(0.3)
        controller.selectOutput(first.id)
        controller.start()
        controller.start()
        XCTAssertEqual(backend.requests, [.refresh])
        controller.stop()
        controller.stop()
        XCTAssertEqual(backend.stops, 1)
        XCTAssertTrue(backend.tokens[0].isCancelled)
        backend.complete(state)
        XCTAssertTrue(controller.outputs.isEmpty)
        XCTAssertFalse(controller.isBusy)
    }

    func testSliderBurstKeepsOnlyLatestPendingValueAndBindsOutputIdentity() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        controller.start()
        backend.complete(state)
        controller.setVolume(0.1)
        for step in 0 ..< 1000 {
            controller.setVolume(Double(step) / 999)
        }
        XCTAssertEqual(backend.requests, [.refresh, .volume(first, 0.1)])
        backend.complete(state)
        XCTAssertEqual(backend.requests.last, .volume(first, 1))
        backend.complete(state)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(backend.requests.count, 3)
        controller.stop()
    }

    func testSelectionDropsOldPendingWritesAndBlocksControlsUntilReadback() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        controller.start()
        backend.complete(state)
        controller.setVolume(0.1)
        controller.setVolume(0.2)
        controller.setMuted(true)
        controller.selectOutput(second.id)
        controller.setVolume(0.9)
        backend.complete(state)
        XCTAssertEqual(backend.requests.last, .select(second))
        var switched = state
        switched.currentDeviceID = second.id
        switched.volume = 0.7
        backend.complete(switched)
        XCTAssertEqual(backend.requests.count, 3)
        XCTAssertEqual(controller.currentDeviceID, second.id)
        XCTAssertEqual(controller.volume, 0.7)
        controller.setMuted(true)
        XCTAssertEqual(backend.requests.last, .mute(second, true))
        controller.stop()
    }

    func testFailurePublishesActualStateAndRefreshDoesNotReplayAWrite() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        controller.start()
        backend.complete(state)
        controller.setMuted(true)
        backend.complete(state, error: .writeFailed)
        XCTAssertFalse(controller.isMuted)
        XCTAssertNotNil(controller.errorMessage)
        backend.onChange?()
        XCTAssertEqual(backend.requests.last, .refresh)
        backend.complete(state)
        XCTAssertNotNil(controller.errorMessage, "An event refresh must not erase the user's failed command")
        controller.refresh()
        backend.complete(state)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(backend.requests.filter {
            if case .mute = $0 {
                return true
            }; return false
        }.count, 1)
        controller.stop()
    }

    func testStopRestartDoesNotRunParallelWorkOrPublishOldResults() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        controller.start()
        controller.stop()
        controller.start()
        for _ in 0 ..< 100 {
            controller.refresh()
        }
        XCTAssertEqual(backend.requests.count, 1)
        backend.complete(state)
        XCTAssertTrue(controller.outputs.isEmpty)
        XCTAssertEqual(backend.requests, [.refresh, .refresh])
        backend.complete(state)
        XCTAssertEqual(controller.outputs, state.outputs)
        controller.stop()
    }

    func testTimeoutCancelsQueuedWritesAndIgnoresLateResultsUntilExplicitRefresh() async {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend, timeout: 0.01)
        controller.start()
        backend.complete(state)
        let timedOut = expectation(description: "Stalled audio command reports a timeout")
        let subscription = controller.$errorMessage.compactMap { $0 }.prefix(1).sink { _ in
            timedOut.fulfill()
        }
        controller.setVolume(0.2)
        controller.setVolume(0.7)
        await fulfillment(of: [timedOut], timeout: 1)
        XCTAssertTrue(backend.tokens[1].isCancelled)
        XCTAssertEqual(backend.requests.count, 2)
        XCTAssertTrue(controller.isBusy, "A stalled worker retains its slot")
        var late = state
        late.volume = 0.2
        backend.complete(late)
        XCTAssertEqual(controller.volume, 0.5, "Late results must not overwrite current UI state")
        XCTAssertEqual(backend.requests.count, 2, "The queued slider write was cancelled")
        XCTAssertFalse(controller.isBusy)
        XCTAssertNotNil(controller.errorMessage)
        controller.refresh()
        XCTAssertEqual(backend.requests.last, .refresh)
        backend.complete(late)
        XCTAssertEqual(controller.volume, 0.2)
        XCTAssertNil(controller.errorMessage)
        controller.stop()
        withExtendedLifetime(subscription) {}
    }

    func testInvalidValuesAndUnknownDevicesNeverBecomeCommands() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        controller.start()
        var unavailable = state
        unavailable.canMute = false
        unavailable.canSetVolume = false
        backend.complete(unavailable)
        controller.setVolume(.nan)
        controller.setVolume(0.5)
        controller.setMuted(true)
        controller.selectOutput(999)
        XCTAssertEqual(backend.requests, [.refresh])
        controller.stop()
    }

    func testOutputEnumerationIsCappedAndCannotEnableAnUnlistedDevice() {
        let backend = Backend()
        let controller = SystemAudioController(backend: backend)
        controller.start()
        var many = state
        many.outputs = (1 ... 200).map { .init(
            id: UInt32($0),
            uid: "device-\($0)",
            name: "Device",
            isBluetooth: false
        ) }
        many.currentDeviceID = 200
        backend.complete(many)
        XCTAssertEqual(controller.outputs.count, 100)
        XCTAssertFalse(controller.canSetVolume)
        XCTAssertFalse(controller.canMute)
        controller.selectOutput(200)
        XCTAssertEqual(backend.requests, [.refresh])
        controller.stop()
    }

    func testIdentityGuardRejectsReusedIDsAndChangedDefaultBeforeWriting() {
        XCTAssertTrue(SystemAudioHardware.matches(
            first,
            live: first,
            current: first.id,
            requiresCurrent: true
        ))
        XCTAssertFalse(SystemAudioHardware.matches(
            first,
            live: nil,
            current: first.id,
            requiresCurrent: true
        ))
        var reused = first
        reused.uid = "reused-id"
        XCTAssertFalse(SystemAudioHardware.matches(
            first,
            live: reused,
            current: first.id,
            requiresCurrent: true
        ))
        XCTAssertFalse(SystemAudioHardware.matches(
            first,
            live: first,
            current: second.id,
            requiresCurrent: true
        ))
        XCTAssertTrue(SystemAudioHardware.matches(
            first,
            live: first,
            current: second.id,
            requiresCurrent: false
        ))
    }

    func testBluetoothUsesPublicTransportAndFallsBackWithoutGuessingModel() {
        XCTAssertTrue(SystemAudioStatusReader.isBluetooth(transport: kAudioDeviceTransportTypeBluetooth))
        XCTAssertTrue(SystemAudioStatusReader.isBluetooth(transport: kAudioDeviceTransportTypeBluetoothLE))
        XCTAssertFalse(SystemAudioStatusReader.isBluetooth(transport: kAudioDeviceTransportTypeHDMI))
        XCTAssertFalse(SystemAudioStatusReader.isBluetooth(transport: nil))
        XCTAssertEqual(SystemAudioStatusReader.bluetoothSymbol(terminals: []), "headphones")
        XCTAssertEqual(
            SystemAudioStatusReader.bluetoothSymbol(terminals: [kAudioStreamTerminalTypeSpeaker]),
            "hifispeaker"
        )
    }
}
