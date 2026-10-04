// Adapted from Macbook Duo Sources/LidSensor.swift and EffectModel.swift (LidReport),
// Copyright (c) 2026 Ruixiang Huang, MIT, commit af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1.
// Modified for Blinker: restartable serial I/O, exact device matching, bounded reports and typed failures.
// See ThirdParty/MacbookDuoEffect for license and attribution.
import Foundation
import IOKit.hid

@MainActor
final class LidAngleReader: LidAngleReadingSource {
    private let queue: DispatchQueue
    private let hardware: LidAngleHardware
    private let lifetime = LidReaderLifetime()

    init() {
        let queue = DispatchQueue(label: "Blinker.ScreenEffects.LidAngle", qos: .utility)
        self.queue = queue
        hardware = LidAngleHardware(queue: queue)
    }

    func read(completion: @escaping @MainActor @Sendable (LidAngleReading) -> Void) {
        let session = lifetime.activate()
        let lifetime = lifetime
        let hardware = hardware
        queue.async {
            guard lifetime.isActive(session) else {
                Task { @MainActor in completion(.init(angle: nil, status: .idle)) }
                return
            }
            let reading = hardware.read()
            if !lifetime.isActive(session) {
                hardware.close()
            }
            Task { @MainActor in completion(reading) }
        }
    }

    func stop() {
        guard lifetime.stopAndQueueCleanup() else { return }
        let hardware = hardware
        let lifetime = lifetime
        queue.async {
            hardware.close()
            lifetime.finishedCleanup()
        }
    }

    deinit {
        let hardware = hardware
        queue.async { hardware.close() }
    }
}

/// Hardware state is confined to this one serial queue; no handle crosses it.
final class LidAngleHardware: @unchecked Sendable {
    private let queue: DispatchQueue
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func read() -> LidAngleReading {
        dispatchPrecondition(condition: .onQueue(queue))
        if device == nil, let failure = connect() {
            return .init(angle: nil, status: failure)
        }
        guard let device else { return .init(angle: nil, status: .unavailable) }
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 1
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess, (3 ... bytes.count).contains(length),
              let angle = Self.decodeReport(Array(bytes.prefix(length))) else {
            close()
            return .init(angle: nil, status: .failed)
        }
        return .init(angle: angle, status: .available)
    }

    /// Feature report 1 carries a little-endian integer degree value, including
    /// 180...360 on hardware that reports that range. Missing bytes are unknown.
    static func decodeReport(_ bytes: [UInt8]) -> Double? {
        guard (3 ... 8).contains(bytes.count), bytes[0] == 1 else { return nil }
        let value = Int(bytes[1]) | (Int(bytes[2]) << 8)
        return value <= 360 ? Double(value) : nil
    }

    private func connect() -> LidSensorStatus? {
        close()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matching: [String: Any] = [kIOHIDVendorIDKey: 0x05AC,
                                       kIOHIDPrimaryUsagePageKey: 0x20,
                                       kIOHIDPrimaryUsageKey: 0x8A]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            close()
            return .failed
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            close()
            return .unavailable
        }
        for candidate in devices.prefix(4) where Self.matches(candidate) {
            if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                device = candidate
                return nil
            }
        }
        close()
        return .failed
    }

    private static func matches(_ candidate: IOHIDDevice) -> Bool {
        let vendor = IOHIDDeviceGetProperty(candidate, kIOHIDVendorIDKey as CFString) as? NSNumber
        let page = IOHIDDeviceGetProperty(candidate, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber
        let usage = IOHIDDeviceGetProperty(candidate, kIOHIDPrimaryUsageKey as CFString) as? NSNumber
        return vendor?.intValue == 0x05AC && page?.intValue == 0x20 && usage?.intValue == 0x8A
    }

    func close() {
        dispatchPrecondition(condition: .onQueue(queue))
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }
}

/// Only lifecycle flags cross queues; all access uses this lock. Cleanup is
/// coalesced across repeated stop/start calls while a hardware read is blocked.
private final class LidReaderLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var active = false
    private var cleanupQueued = false

    func activate() -> UInt64 {
        lock.withLock {
            active = true
            return generation
        }
    }

    func isActive(_ session: UInt64) -> Bool {
        lock.withLock { active && session == generation }
    }

    func stopAndQueueCleanup() -> Bool {
        lock.withLock {
            active = false
            generation &+= 1
            guard !cleanupQueued else { return false }
            cleanupQueued = true
            return true
        }
    }

    func finishedCleanup() {
        lock.withLock { cleanupQueued = false }
    }
}
