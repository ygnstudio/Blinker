// Adapted from Status Trio CoreAudioOutputController, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: serialized operations, cancellation and device identity guards.
// See ThirdParty/StatusTrio for license and attribution.
import Foundation

@MainActor
final class CoreAudioBackend: SystemAudioOperating {
    var onChange: (@MainActor @Sendable () -> Void)?
    private let queue: DispatchQueue
    private let hardware: SystemAudioHardware
    private let lifetime = SystemStatusReaderLifetime()

    init() {
        let queue = DispatchQueue(label: "Blinker.Audio.Control", qos: .utility)
        self.queue = queue
        hardware = SystemAudioHardware(queue: queue)
    }

    func perform(_ request: SystemAudioRequest, cancellation: SystemAudioCancellation,
                 completion: @escaping @MainActor @Sendable (SystemAudioResult) -> Void) {
        let generation = lifetime.activate()
        let lifetime = lifetime
        let hardware = hardware
        let changed: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
        queue.async {
            guard lifetime.isActive(generation), !cancellation.isCancelled else {
                Task { @MainActor in completion(.init(state: .empty)) }
                return
            }
            let result = hardware.perform(request, cancellation: cancellation, onChange: changed)
            if !lifetime.isActive(generation) {
                hardware.stop()
            }
            Task { @MainActor in completion(result) }
        }
    }

    func stop() {
        guard lifetime.stopAndQueueCleanup() else { return }
        let lifetime = lifetime
        let hardware = hardware
        queue.async {
            hardware.stop()
            lifetime.finishedCleanup()
        }
    }

    deinit {
        let hardware = hardware
        queue.async { hardware.stop() }
    }
}
