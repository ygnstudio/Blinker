// Adapted from Status Trio Audio/CoreAudioOutputController.swift, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: bounded enumeration, explicit output identity and public CoreAudio only.
// See ThirdParty/StatusTrio for license and attribution.
import CoreAudio
import Foundation

/// Mutable CoreAudio registrations stay on one private serial queue. Entry
/// points assert confinement, which makes passing this owner between closures safe.
final class SystemAudioHardware: @unchecked Sendable {
    private let queue: DispatchQueue
    private let reader: SystemAudioStatusReader
    private let system = AudioObjectID(kAudioObjectSystemObject)

    init(queue: DispatchQueue) {
        self.queue = queue
        reader = SystemAudioStatusReader(queue: queue)
    }

    func perform(_ request: SystemAudioRequest, cancellation: SystemAudioCancellation,
                 onChange: @escaping @Sendable () -> Void) -> SystemAudioResult {
        dispatchPrecondition(condition: .onQueue(queue))
        var failure: SystemAudioFailure?
        do {
            try execute(request, cancellation: cancellation)
        } catch {
            failure = error as? SystemAudioFailure ?? .writeFailed
        }
        do {
            return try .init(state: read(onChange: onChange), error: failure)
        } catch {
            return .init(state: .empty, error: failure ?? .unavailable)
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        reader.stop()
    }

    private func read(onChange: @escaping @Sendable () -> Void) throws -> SystemAudioState {
        let initialDevice = reader.defaultOutputDevice()
        let volume = reader.read(onChange: onChange)
        guard let identifiers = reader.identifiers(object: system, selector: kAudioHardwarePropertyDevices,
                                                   scope: kAudioObjectPropertyScopeGlobal, maximum: 100)
        else { throw SystemAudioFailure.unavailable }
        let current = reader.defaultOutputDevice()
        guard current == initialDevice else { throw SystemAudioFailure.deviceChanged }
        let outputs = identifiers.compactMap(output).sorted {
            if ($0.id == current) != ($1.id == current) {
                return $0.id == current
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let input = readInput()
        guard let current, outputs.contains(where: { $0.id == current }) else {
            return .init(outputs: outputs, input: input)
        }
        return .init(outputs: outputs, currentDeviceID: current, volume: volume?.scalar,
                     isMuted: volume?.isMuted ?? false,
                     canSetVolume: volume?.scalar != nil && !writableElements(
                         current,
                         selector: kAudioDevicePropertyVolumeScalar
                     ).isEmpty,
                     canMute: !writableElements(current, selector: kAudioDevicePropertyMute).isEmpty,
                     input: input)
    }

    /// The default input device, or nil when the Mac has none (rare) or it
    /// vanished mid-read. Input controls use the input scope throughout.
    private func readInput() -> SystemAudioInput? {
        guard let device = reader.defaultInputDevice(),
              device != kAudioObjectUnknown,
              reader.uint32(object: device, selector: kAudioObjectPropertyClass,
                            scope: kAudioObjectPropertyScopeGlobal,
                            element: kAudioObjectPropertyElementMain) == kAudioDeviceClassID,
              reader.uint32(object: device, selector: kAudioDevicePropertyDeviceIsAlive,
                            scope: kAudioObjectPropertyScopeGlobal,
                            element: kAudioObjectPropertyElementMain) == 1
        else { return nil }
        let name = string(device, selector: kAudioObjectPropertyName)
            ?? String(localized: "音频输入设备")
        let volume = inputScalar(device)
        let muted = reader.uint32(object: device, selector: kAudioDevicePropertyMute,
                                  scope: kAudioObjectPropertyScopeInput,
                                  element: kAudioObjectPropertyElementMain).map { $0 != 0 } ?? false
        let inUse = reader.uint32(object: device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                  scope: kAudioObjectPropertyScopeGlobal,
                                  element: kAudioObjectPropertyElementMain).map { $0 != 0 } ?? false
        return SystemAudioInput(
            deviceID: device, name: name, volume: volume, isMuted: muted,
            canSetVolume: !writableInputElements(device, selector: kAudioDevicePropertyVolumeScalar).isEmpty,
            canMute: !writableInputElements(device, selector: kAudioDevicePropertyMute).isEmpty,
            isInUse: inUse
        )
    }

    private func inputScalar(_ device: AudioDeviceID) -> Double? {
        var address = property(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<Float32>.size, value.isFinite, (0 ... 1).contains(value)
        else { return nil }
        return Double(value)
    }

    private func execute(_ request: SystemAudioRequest, cancellation: SystemAudioCancellation) throws {
        guard !cancellation.isCancelled else { return }
        switch request {
        case .refresh: return
        case let .select(target): try select(target, cancellation: cancellation)
        case let .volume(target, scalar): try setVolume(scalar, target: target, cancellation: cancellation)
        case let .mute(target, muted): try setMuted(muted, target: target, cancellation: cancellation)
        case let .inputVolume(scalar): try setInputVolume(scalar, cancellation: cancellation)
        case let .inputMute(muted): try setInputMuted(muted, cancellation: cancellation)
        }
    }

    /// Input commands address whichever device is the default *at write time*,
    /// re-read between elements so a mid-write switch cannot leak onto the
    /// next device.
    private func setInputVolume(_ scalar: Double, cancellation: SystemAudioCancellation) throws {
        guard scalar.isFinite, (0 ... 1).contains(scalar) else { throw SystemAudioFailure.unsupported }
        guard let device = currentInputDevice(cancellation: cancellation) else {
            throw SystemAudioFailure.deviceChanged
        }
        let elements = writableInputElements(device, selector: kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { throw SystemAudioFailure.unsupported }
        for element in elements {
            guard currentInputDevice(cancellation: cancellation) == device else {
                throw SystemAudioFailure.deviceChanged
            }
            var address = property(kAudioDevicePropertyVolumeScalar,
                                   scope: kAudioObjectPropertyScopeInput, element: element)
            var value = Float32(scalar)
            guard !cancellation.isCancelled,
                  AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value) == noErr
            else { throw SystemAudioFailure.writeFailed }
        }
    }

    private func setInputMuted(_ muted: Bool, cancellation: SystemAudioCancellation) throws {
        guard let device = currentInputDevice(cancellation: cancellation) else {
            throw SystemAudioFailure.deviceChanged
        }
        let elements = writableInputElements(device, selector: kAudioDevicePropertyMute)
        guard !elements.isEmpty else { throw SystemAudioFailure.unsupported }
        for element in elements {
            guard currentInputDevice(cancellation: cancellation) == device else {
                throw SystemAudioFailure.deviceChanged
            }
            var address = property(kAudioDevicePropertyMute,
                                   scope: kAudioObjectPropertyScopeInput, element: element)
            var value: UInt32 = muted ? 1 : 0
            guard !cancellation.isCancelled,
                  AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value) == noErr
            else { throw SystemAudioFailure.writeFailed }
        }
    }

    private func currentInputDevice(cancellation: SystemAudioCancellation) -> AudioDeviceID? {
        guard !cancellation.isCancelled,
              let device = reader.defaultInputDevice(), device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    private func select(_ target: SystemAudioOutput, cancellation: SystemAudioCancellation) throws {
        try validate(target, requiresCurrent: false, cancellation: cancellation)
        var address = property(kAudioHardwarePropertyDefaultOutputDevice,
                               scope: kAudioObjectPropertyScopeGlobal)
        var value = target.id
        guard isSettable(system, address: address), !cancellation.isCancelled,
              AudioObjectSetPropertyData(system, &address, 0, nil, 4, &value) == noErr,
              reader.defaultOutputDevice() == target.id else { throw SystemAudioFailure.writeFailed }
    }

    private func setVolume(_ scalar: Double, target: SystemAudioOutput,
                           cancellation: SystemAudioCancellation) throws {
        guard scalar.isFinite, (0 ... 1).contains(scalar) else { throw SystemAudioFailure.unsupported }
        try validate(target, requiresCurrent: true, cancellation: cancellation)
        let elements = writableElements(target.id, selector: kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { throw SystemAudioFailure.unsupported }
        for element in elements {
            try validate(target, requiresCurrent: true, cancellation: cancellation)
            var address = property(kAudioDevicePropertyVolumeScalar, element: element)
            var value = Float32(scalar)
            guard !cancellation.isCancelled,
                  AudioObjectSetPropertyData(target.id, &address, 0, nil, 4, &value) == noErr
            else { throw SystemAudioFailure.writeFailed }
        }
    }

    private func setMuted(_ muted: Bool, target: SystemAudioOutput,
                          cancellation: SystemAudioCancellation) throws {
        try validate(target, requiresCurrent: true, cancellation: cancellation)
        let elements = writableElements(target.id, selector: kAudioDevicePropertyMute)
        guard !elements.isEmpty else { throw SystemAudioFailure.unsupported }
        for element in elements {
            try validate(target, requiresCurrent: true, cancellation: cancellation)
            var address = property(kAudioDevicePropertyMute, element: element)
            var value: UInt32 = muted ? 1 : 0
            guard !cancellation.isCancelled,
                  AudioObjectSetPropertyData(target.id, &address, 0, nil, 4, &value) == noErr
            else { throw SystemAudioFailure.writeFailed }
        }
    }

    private func validate(_ target: SystemAudioOutput, requiresCurrent: Bool,
                          cancellation: SystemAudioCancellation) throws {
        guard !cancellation.isCancelled,
              Self.matches(target, live: output(target.id), current: reader.defaultOutputDevice(),
                           requiresCurrent: requiresCurrent)
        else { throw SystemAudioFailure.deviceChanged }
    }

    static func matches(_ target: SystemAudioOutput, live: SystemAudioOutput?, current: UInt32?,
                        requiresCurrent: Bool) -> Bool {
        guard let live, live.id == target.id, live.uid == target.uid else { return false }
        return !requiresCurrent || current == target.id
    }

    private func output(_ id: AudioDeviceID) -> SystemAudioOutput? {
        guard id != kAudioObjectUnknown,
              reader.uint32(object: id, selector: kAudioObjectPropertyClass,
                            scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
              == kAudioDeviceClassID,
              reader.uint32(object: id, selector: kAudioDevicePropertyDeviceIsAlive,
                            scope: kAudioObjectPropertyScopeGlobal,
                            element: kAudioObjectPropertyElementMain) ==
              1,
              reader.uint32(object: id, selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                            scope: kAudioObjectPropertyScopeOutput,
                            element: kAudioObjectPropertyElementMain) ==
              1,
              reader.uint32(object: id, selector: kAudioDevicePropertyIsHidden,
                            scope: kAudioObjectPropertyScopeGlobal,
                            element: kAudioObjectPropertyElementMain) !=
              1,
              !reader.outputChannels(id).isEmpty,
              let uid = string(id, selector: kAudioDevicePropertyDeviceUID), !uid.isEmpty else { return nil }
        let name = string(id, selector: kAudioObjectPropertyName) ?? String(localized: "音频输出设备")
        return .init(id: id, uid: uid, name: name, isBluetooth: reader.isBluetooth(id))
    }

    private func writableElements(_ device: AudioDeviceID,
                                  selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        if isSettable(device, address: property(selector)) {
            return [kAudioObjectPropertyElementMain]
        }
        return reader.outputChannels(device).filter { isSettable(
            device,
            address: property(selector, element: $0)
        ) }
    }

    private func writableInputElements(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        if isSettable(device, address: property(selector, scope: kAudioObjectPropertyScopeInput)) {
            return [kAudioObjectPropertyElementMain]
        }
        return reader.inputChannels(device).filter { isSettable(
            device,
            address: property(selector, scope: kAudioObjectPropertyScopeInput, element: $0)
        ) }
    }

    private func isSettable(_ device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func property(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }

    private func string(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = property(selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        let string = value.takeRetainedValue() as String
        guard !string.isEmpty, string.utf8.count <= 4096 else { return nil }
        return string
    }
}
