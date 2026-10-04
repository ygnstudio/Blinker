// Adapted from Status Trio VolumeMonitor/CoreAudioOutputChannelElements,
// Copyright 2026 lingyired, Apache-2.0, commit d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: read-only default output, bounded channels, no DDC or identifying metadata.
// See ThirdParty/StatusTrio for license and attribution.
import CoreAudio
import Foundation

/// Sendable only by queue confinement: the owner exposes no hardware state,
/// and every read, listener mutation, and teardown runs on its one serial queue.
/// Entry-point preconditions enforce that invariant; callbacks only signal change.
final class SystemAudioStatusReader: @unchecked Sendable {
    private struct Registration {
        var object: AudioObjectID
        var address: AudioObjectPropertyAddress
        var queue: DispatchQueue
        var block: AudioObjectPropertyListenerBlock
    }

    private let queue: DispatchQueue
    private var systemListener: Registration?
    private var devicesListener: Registration?
    private var deviceListeners: [Registration] = []
    private var device: AudioDeviceID?
    private var listenedChannels: [AudioObjectPropertyElement] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func read(onChange: @escaping @Sendable () -> Void) -> MenuBarSystemSnapshot.Volume? {
        dispatchPrecondition(condition: .onQueue(queue))
        installSystemListeners(onChange: onChange)
        let current = uint32(object: AudioObjectID(kAudioObjectSystemObject),
                             selector: kAudioHardwarePropertyDefaultOutputDevice,
                             scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
        let valid = current.flatMap { candidate -> AudioDeviceID? in
            guard candidate != kAudioObjectUnknown,
                  uint32(object: candidate, selector: kAudioObjectPropertyClass,
                         scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
                  == kAudioDeviceClassID,
                  uint32(object: candidate, selector: kAudioDevicePropertyDeviceIsAlive,
                         scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain) ==
                  1
            else { return nil }
            return candidate
        }
        let channels = valid.map(outputChannels) ?? []
        if valid != device || channels != listenedChannels {
            deviceListeners.forEach(remove)
            deviceListeners.removeAll()
            device = valid
            listenedChannels = channels
        }
        guard let device = valid else { return nil }
        let elements = [kAudioObjectPropertyElementMain] + channels
        reconcileListeners(device: device, elements: elements, queue: queue, onChange: onChange)
        let mainVolume = scalar(device: device, element: kAudioObjectPropertyElementMain)
        let channelVolumes = mainVolume == nil ? channels
            .compactMap { scalar(device: device, element: $0) } : []
        let volume = mainVolume ?? Self.average(channelVolumes)
        let mainMute = uint32(object: device, selector: kAudioDevicePropertyMute,
                              scope: kAudioObjectPropertyScopeOutput,
                              element: kAudioObjectPropertyElementMain)
        let channelMutes = channels.compactMap {
            uint32(object: device, selector: kAudioDevicePropertyMute,
                   scope: kAudioObjectPropertyScopeOutput, element: $0)
        }
        let muted = mainMute
            .map { $0 != 0 } ?? (!channelMutes.isEmpty && channelMutes.allSatisfy { $0 != 0 })
        let bluetooth = isBluetooth(device)
        return .init(scalar: volume, isMuted: muted, isBluetooth: bluetooth,
                     symbolName: bluetooth ? bluetoothSymbol(device) : nil)
    }

    private func installSystemListeners(onChange: @escaping @Sendable () -> Void) {
        if systemListener == nil {
            let address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            systemListener = listen(object: AudioObjectID(kAudioObjectSystemObject), address: address,
                                    queue: queue, onChange: onChange)
        }
        if devicesListener == nil {
            let address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            devicesListener = listen(object: AudioObjectID(kAudioObjectSystemObject), address: address,
                                     queue: queue, onChange: onChange)
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        if let systemListener {
            remove(systemListener)
        }
        systemListener = nil
        if let devicesListener {
            remove(devicesListener)
        }
        devicesListener = nil
        deviceListeners.forEach(remove)
        deviceListeners.removeAll()
        device = nil
        listenedChannels = []
    }

    func defaultOutputDevice() -> AudioDeviceID? {
        uint32(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
    }

    func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let transport = uint32(object: device, selector: kAudioDevicePropertyTransportType,
                               scope: kAudioObjectPropertyScopeGlobal,
                               element: kAudioObjectPropertyElementMain)
        return Self.isBluetooth(transport: transport)
    }

    static func isBluetooth(transport: UInt32?) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private func bluetoothSymbol(_ device: AudioDeviceID) -> String {
        let streams = identifiers(object: device, selector: kAudioDevicePropertyStreams,
                                  scope: kAudioObjectPropertyScopeOutput, maximum: 32) ?? []
        let terminals = streams.compactMap {
            uint32(object: $0, selector: kAudioStreamPropertyTerminalType,
                   scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
        }
        return Self.bluetoothSymbol(terminals: terminals)
    }

    static func bluetoothSymbol(terminals: [UInt32]) -> String {
        terminals.contains(kAudioStreamTerminalTypeSpeaker) ? "hifispeaker" : "headphones"
    }

    func identifiers(object: AudioObjectID, selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope, maximum: Int) -> [UInt32]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size % 4 == 0, Int(size) <= maximum * 4 else { return nil }
        guard size > 0 else { return [] }
        var values = [UInt32](repeating: 0, count: Int(size) / 4)
        let capacity = size
        let status = values.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr, size <= capacity, size % 4 == 0 else { return nil }
        return Array(values.prefix(Int(size) / 4))
    }

    static func average(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && (0 ... 1).contains($0) }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private func reconcileListeners(device: AudioDeviceID, elements: [AudioObjectPropertyElement],
                                    queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        for element in elements {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                guard !deviceListeners.contains(where: {
                    $0.address.mSelector == selector && $0.address.mElement == element
                }) else { continue }
                let address = AudioObjectPropertyAddress(mSelector: selector,
                                                         mScope: kAudioObjectPropertyScopeOutput,
                                                         mElement: element)
                if let listener = listen(object: device, address: address, queue: queue, onChange: onChange) {
                    deviceListeners.append(listener)
                }
            }
        }
    }

    private func listen(object: AudioObjectID, address: AudioObjectPropertyAddress,
                        queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) -> Registration? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        return .init(object: object, address: address, queue: queue, block: block)
    }

    private func remove(_ registration: Registration) {
        var address = registration.address
        AudioObjectRemovePropertyListenerBlock(
            registration.object,
            &address,
            registration.queue,
            registration.block
        )
    }

    private func scalar(device: AudioDeviceID, element: AudioObjectPropertyElement) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                 mScope: kAudioObjectPropertyScopeOutput, mElement: element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<Float32>.size, value.isFinite,
              (0 ... 1).contains(value) else { return nil }
        return Double(value)
    }

    func uint32(object: AudioObjectID, selector: AudioObjectPropertySelector,
                scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<UInt32>.size else { return nil }
        return value
    }

    func outputChannels(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size <= 65536 else { return [] }
        let allocation = Int(size)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: allocation,
                                                       alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr,
              size <= allocation, size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        let headerSize = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) ?? MemoryLayout<UInt32>.size
        guard count <= 64, headerSize + count * MemoryLayout<AudioBuffer>.size <= Int(size) else { return [] }
        let channels = UnsafeMutableAudioBufferListPointer(list).reduce(0) { count, buffer in
            min(32, count + Int(min(32, buffer.mNumberChannels)))
        }
        return channels > 0 ? (1 ... channels).map(AudioObjectPropertyElement.init) : []
    }
}
