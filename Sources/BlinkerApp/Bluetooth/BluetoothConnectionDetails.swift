import Foundation
import IOBluetooth

/// A2DP codec and disconnect for connected devices. These go through
/// IOBluetooth, which macOS gates behind the same Bluetooth privacy grant
/// as the nearby scan — so every entry point here is reachable only after
/// the user has opted in and the grant is confirmed (the read option and
/// the panel both check authorization first). The codec property itself is
/// undocumented; unknown identifiers stay hidden rather than labeled.
enum BluetoothConnectionDetails {
    /// A2DP codec reported by the system. Only values corroborated across
    /// macOS releases map to a name; everything else is treated as unknown.
    enum AudioCodec: String, Equatable, Sendable, CaseIterable {
        case sbc = "SBC"
        case aac = "AAC"
        case aptX = "aptX"

        /// The system's numeric codec identifier.
        static func mapped(from raw: Int) -> AudioCodec? {
            switch raw {
            case 0: .sbc
            case 2: .aac
            case 4: .aptX
            default: nil
            }
        }
    }

    /// The codec for one device; nil when unreachable, not streaming audio,
    /// or reporting an identifier macOS is not known to negotiate.
    static func codec(address: String) -> AudioCodec? {
        guard let device = IOBluetoothDevice(addressString: address),
              device.isConnected() else { return nil }
        // "AVCodec" is undocumented and exists only while A2DP streams. On
        // every other connected device (keyboards, mice, idle headsets)
        // KVC raises NSUndefinedKeyException, which Swift cannot catch —
        // the read aborted the process on the SystemRead queue. Probe the
        // getter first so non-audio devices fall through as "no codec".
        let key = "AVCodec"
        guard device.responds(to: Selector(key)) else { return nil }
        return (device.value(forKey: key) as? NSNumber)
            .flatMap { AudioCodec.mapped(from: $0.intValue) }
    }

    /// Attaches codecs to the connected entries of a profiler read. The
    /// lookup is injectable so tests never touch IOBluetooth (whose privacy
    /// gate terminates unentitled processes outright).
    static func attachingCodecs(
        to devices: [BluetoothDevice],
        lookup: (String) -> AudioCodec? = codec(address:)
    ) -> [BluetoothDevice] {
        devices.map { device in
            guard device.isConnected, let codec = lookup(device.id) else { return device }
            var enriched = device
            enriched.audioCodec = codec
            return enriched
        }
    }

    /// Ends the current connection; the pairing survives and the device can
    /// be reconnected from System Settings at any time.
    @discardableResult
    static func disconnect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address),
              device.isConnected() else { return false }
        return device.closeConnection() == kIOReturnSuccess
    }

    /// Reconnects a paired device. The open call is injectable so tests
    /// stay on the delegation surface and never touch IOBluetooth (whose
    /// privacy gate terminates unentitled processes outright).
    @discardableResult
    static func connect(address: String, open: (String) -> Bool = openConnection(address:)) -> Bool {
        open(address)
    }

    /// The real IOBluetooth open. An already-connected device reports
    /// success without re-opening the link, mirroring the disconnect
    /// guard; unknown addresses report failure.
    static func openConnection(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() { return true }
        return device.openConnection() == kIOReturnSuccess
    }
}
