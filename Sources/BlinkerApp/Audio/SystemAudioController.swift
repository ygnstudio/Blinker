import Combine
import Foundation

/// User commands are bound to a device identity. A slider burst retains only
/// its newest value, while a device switch drops writes for the previous output.
@MainActor
final class SystemAudioController: ObservableObject {
    @Published private(set) var outputs: [SystemAudioOutput] = []
    @Published private(set) var currentDeviceID: UInt32?
    @Published private(set) var volume: Double?
    @Published private(set) var isMuted = false
    @Published private(set) var canSetVolume = false
    @Published private(set) var canMute = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    var onChange: (() -> Void)?

    private let backend: any SystemAudioOperating
    private let timeout: TimeInterval
    private var running = false
    private var generation: UInt64 = 0
    private var inFlight: SystemAudioRequest?
    private var cancellation: SystemAudioCancellation?
    private var pendingSelection: SystemAudioRequest?
    private var pendingVolume: SystemAudioRequest?
    private var pendingMute: SystemAudioRequest?
    private var refreshPending = false
    private var deadline: Timer?

    convenience init() {
        self.init(backend: CoreAudioBackend())
    }

    init(backend: any SystemAudioOperating, timeout: TimeInterval = 5) {
        self.backend = backend
        self.timeout = timeout
        backend.onChange = { [weak self] in
            guard let self, running else { return }
            refreshPending = true
            drain()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        generation &+= 1
        if let cancellation {
            isBusy = true
            armDeadline(session: generation, token: cancellation)
        }
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        generation &+= 1
        cancellation?.cancel()
        clearPending()
        deadline?.invalidate()
        deadline = nil
        isBusy = false
        backend.stop()
        apply(.empty)
        errorMessage = nil
    }

    func refresh() {
        guard running else { return }
        errorMessage = nil
        refreshPending = true
        drain()
    }

    func setVolume(_ value: Double) {
        guard running, value.isFinite, canSetVolume, !isSwitching,
              let target = currentOutput else { return }
        pendingVolume = .volume(target, min(1, max(0, value)))
        drain()
    }

    func setMuted(_ value: Bool) {
        guard running, canMute, !isSwitching, let target = currentOutput else { return }
        pendingMute = .mute(target, value)
        drain()
    }

    func selectOutput(_ id: UInt32) {
        guard running, let target = outputs.first(where: { $0.id == id }) else { return }
        pendingSelection = .select(target)
        pendingVolume = nil
        pendingMute = nil
        drain()
    }

    private var currentOutput: SystemAudioOutput? {
        outputs.first { $0.id == currentDeviceID }
    }

    private var isSwitching: Bool {
        if let inFlight, case .select = inFlight {
            return true
        }
        return pendingSelection != nil
    }

    private func drain() {
        guard running, inFlight == nil else { return }
        guard let request = takeNextRequest() else {
            isBusy = false
            return
        }
        inFlight = request
        isBusy = true
        if request != .refresh {
            errorMessage = nil
        }
        let session = generation
        let token = SystemAudioCancellation()
        cancellation = token
        armDeadline(session: session, token: token)
        backend.perform(request, cancellation: token) { [weak self] result in
            guard let self else { return }
            inFlight = nil
            cancellation = nil
            deadline?.invalidate()
            deadline = nil
            guard running else { return }
            if generation == session, !token.isCancelled {
                apply(result.state)
                if let error = result.error {
                    errorMessage = error.message
                } else if request != .refresh {
                    errorMessage = nil
                }
                if request != .refresh {
                    onChange?()
                }
            }
            drain()
        }
    }

    private func takeNextRequest() -> SystemAudioRequest? {
        if let selection = pendingSelection {
            pendingSelection = nil
            return selection
        } else if let volume = pendingVolume {
            pendingVolume = nil
            return volume
        } else if let mute = pendingMute {
            pendingMute = nil
            return mute
        } else if refreshPending {
            refreshPending = false
            return .refresh
        }
        return nil
    }

    private func armDeadline(session: UInt64, token: SystemAudioCancellation) {
        deadline?.invalidate()
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, running, generation == session, cancellation === token else { return }
                errorMessage = SystemAudioFailure.timedOut.message
                token.cancel()
                clearPending()
                // Keep the in-flight slot until CoreAudio returns; never add workers.
            }
        }
        deadline = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func apply(_ state: SystemAudioState) {
        var seen = Set<UInt32>()
        outputs = Array(state.outputs.filter { seen.insert($0.id).inserted }.prefix(100))
        currentDeviceID = state.currentDeviceID
        volume = state.volume.flatMap { $0.isFinite && (0 ... 1).contains($0) ? $0 : nil }
        isMuted = state.isMuted
        canSetVolume = state.canSetVolume && currentOutput != nil
        canMute = state.canMute && currentOutput != nil
    }

    private func clearPending() {
        pendingSelection = nil
        pendingVolume = nil
        pendingMute = nil
        refreshPending = false
    }

    deinit {
        cancellation?.cancel()
        deadline?.invalidate()
    }
}
