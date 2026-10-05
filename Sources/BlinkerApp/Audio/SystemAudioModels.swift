import Foundation

struct SystemAudioOutput: Identifiable, Equatable, Sendable {
    var id: UInt32
    var uid: String
    var name: String
    var isBluetooth: Bool
}

/// The default input device as the panel shows it. Read-only identity plus
/// the controls the device actually supports; unsupported controls stay nil/false.
struct SystemAudioInput: Equatable, Sendable {
    var deviceID: UInt32
    var name: String
    var volume: Double?
    var isMuted = false
    var canSetVolume = false
    var canMute = false
    /// Some process is currently capturing from this device.
    var isInUse = false
}

struct SystemAudioState: Equatable, Sendable {
    var outputs: [SystemAudioOutput] = []
    var currentDeviceID: UInt32?
    var volume: Double?
    var isMuted = false
    var canSetVolume = false
    var canMute = false
    var input: SystemAudioInput?
    static let empty = Self()
}

enum SystemAudioRequest: Equatable, Sendable {
    case refresh
    case volume(SystemAudioOutput, Double)
    case mute(SystemAudioOutput, Bool)
    case select(SystemAudioOutput)
    case inputVolume(Double)
    case inputMute(Bool)
}

enum SystemAudioFailure: Error, Sendable {
    case unavailable
    case deviceChanged
    case unsupported
    case writeFailed
    case timedOut

    var message: String {
        switch self {
        case .unavailable: String(localized: "无法读取音频输出设备，请稍后重试。")
        case .deviceChanged: String(localized: "音频输出已改变，请重新调整。")
        case .unsupported: String(localized: "此输出设备不支持这项控制。")
        case .writeFailed: String(localized: "音频设置未能完成，请重试。")
        case .timedOut: String(localized: "系统音频服务未响应，请稍后重试。")
        }
    }
}

struct SystemAudioResult: Sendable {
    var state: SystemAudioState
    var error: SystemAudioFailure?
}

/// Only cancellation crosses queues; all accesses use the same lock.
final class SystemAudioCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

@MainActor
protocol SystemAudioOperating: AnyObject {
    var onChange: (@MainActor @Sendable () -> Void)? { get set }
    func perform(_ request: SystemAudioRequest, cancellation: SystemAudioCancellation,
                 completion: @escaping @MainActor @Sendable (SystemAudioResult) -> Void)
    func stop()
}
