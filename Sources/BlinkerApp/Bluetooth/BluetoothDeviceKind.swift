// Device-kind wording tables adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: flattened enum (icons need no nested forms).
// See ThirdParty/StatusTrio for license and attribution.
import Foundation

/// The class a paired device declares, flattened to one level: the panel only
/// needs enough discrimination to pick an icon.
enum BluetoothDeviceKind: String, Equatable, Sendable, CaseIterable {
    case laptop, desktop, computer
    case phone, tablet, watch
    case audio
    case keyboard, mouse, trackpad, gamepad, peripheral
    case printer, scanner, camera, display, imaging
    case toy, health, unknown

    /// SF Symbols for panel rows. There is no Bluetooth rune and no trackpad
    /// glyph in SF Symbols; those fall back to the nearest readable shape.
    var symbolName: String {
        switch self {
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .computer: "macmini"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .watch: "applewatch"
        case .audio: "headphones"
        case .keyboard: "keyboard"
        case .mouse, .trackpad: "computermouse"
        case .gamepad: "gamecontroller"
        case .peripheral: "cable.connector"
        case .printer: "printer"
        case .scanner: "scanner"
        case .camera, .imaging: "camera"
        case .display: "display"
        case .toy: "teddybear"
        case .health: "waveform.path.ecg"
        case .unknown: "antenna.radiowaves.left.and.right"
        }
    }
}

/// Maps the wording macOS reports in the Bluetooth profiler report to a kind.
/// The tables cover the strings macOS has actually emitted, newest first:
/// macOS 26 reports `device_minorType` only, older releases also carry the
/// `*_string` variants. Substring rules run in order: `headphone` must be
/// tested before `phone`, or headsets become phones.
enum BluetoothDeviceKindResolver {
    private static let minorKeys = ["device_minorType", "device_minorClassOfDevice_string"]
    private static let majorKeys = ["device_majorType", "device_majorClassOfDevice_string"]

    static func kind(properties: [String: Any]) -> BluetoothDeviceKind {
        for key in minorKeys {
            if let wording = normalized(properties[key]) {
                if let exact = minorKindsByWording[wording] { return exact }
                if let matched = containsRules.first(where: { wording.contains($0.token) })?.kind {
                    return matched
                }
            }
        }
        for key in majorKeys {
            if let wording = normalized(properties[key]) {
                if let exact = majorKindsByWording[wording] { return exact }
                if let matched = majorContainsRules.first(where: { wording.contains($0.token) })?.kind {
                    return matched
                }
            }
        }
        return .unknown
    }

    private static func normalized(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let wording = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        return wording.isEmpty ? nil : wording
    }

    // MARK: Exact minor wording

    private static let minorKindsByWording: [String: BluetoothDeviceKind] = {
        var table: [String: BluetoothDeviceKind] = [:]
        func add(_ kind: BluetoothDeviceKind, _ wordings: [String]) {
            for wording in wordings { table[wording] = kind }
        }
        add(.laptop, ["laptop", "notebook", "laptopcomputer"])
        add(.desktop, ["desktop", "desktopcomputer", "desktopworkstation", "workstation",
                       "server", "serverclasscomputer"])
        add(.computer, ["computer", "computeruncategorized", "handheldpc", "handheldpcpda",
                        "pda", "palmsizedpc", "palmsizepcpda", "wearablecomputer"])
        add(.tablet, ["tablet", "tabletcomputer"])
        add(.phone, ["smartphone", "cellphone", "cellular", "cellularphone", "cordless",
                     "cordlessphone", "wiredmodem", "voicegateway", "wiredmodemorvoicegateway",
                     "isdn", "commonisdnaccess", "phone", "phoneuncategorized"])
        add(.watch, ["watch", "wristwatch"])
        add(.audio, ["headphones", "headphone", "wearableheadset", "headset", "handsfree",
                     "loudspeaker", "speaker", "hifi", "hifiaudio", "microphone", "portableaudio",
                     "caraudio", "settopbox", "vcr", "videocamera", "camcorder", "videomonitor",
                     "videodisplayandloudspeaker", "videoconferencing", "audio", "audiovideo",
                     "audiovideounclassified"])
        add(.keyboard, ["keyboard", "keypad", "combinedkeyboardpointing", "keyboardpointingdevice"])
        add(.mouse, ["mouse", "pointingdevice", "pointer", "trackball"])
        add(.trackpad, ["trackpad", "touchpad", "digitizertablet"])
        add(.gamepad, ["gamepad", "joystick", "gamecontroller", "controller"])
        add(.peripheral, ["remotecontrol", "sensingdevice", "cardreader", "digitalpen",
                          "barcodescanner", "handheldbarcodescanner",
                          "handheldgestureinputdevice", "peripheral", "peripheraluncategorized",
                          "input"])
        add(.printer, ["printer"])
        add(.scanner, ["scanner"])
        add(.camera, ["camera"])
        add(.display, ["display", "monitor", "projector"])
        add(.imaging, ["imaging", "imaginguncategorized"])
        add(.toy, ["toy", "robot", "vehicle", "dollactionfigure", "game", "videogamingtoy"])
        add(.health, ["health", "bloodpressure", "bloodpressuremonitor", "thermometer", "scale",
                      "weighingscale", "glucosemeter", "pulseoximeter", "pulserate",
                      "pulseratemonitor", "heartrate", "heartratemonitor", "healthdatadisplay"])
        add(.unknown, ["miscellaneous", "uncategorized", "unclassified", "unknown", "none", "any",
                       "networkaccesspoint", "lanaccesspoint", "accesspoint"])
        return table
    }()

    // MARK: Ordered substring rules (minor wording)

    private static let containsRules: [(token: String, kind: BluetoothDeviceKind)] = [
        ("touchpad", .trackpad), ("trackpad", .trackpad), ("digitizer", .trackpad),
        ("keyboard", .keyboard), ("keypad", .keyboard),
        ("gamepad", .gamepad), ("gamecontroller", .gamepad), ("joystick", .gamepad),
        ("mouse", .mouse), ("trackball", .mouse), ("pointing", .mouse),
        ("headphone", .audio), ("earphone", .audio), ("earbud", .audio), ("headset", .audio),
        ("speaker", .audio), ("microphone", .audio), ("hifi", .audio),
        ("tablet", .tablet),
        ("watch", .watch),
        ("laptop", .laptop), ("notebook", .laptop),
        ("desktop", .desktop), ("workstation", .desktop), ("server", .desktop),
        ("smartphone", .phone), ("cellular", .phone),
        ("printer", .printer), ("scanner", .scanner),
        ("camera", .camera),
        ("projector", .display), ("monitor", .display), ("display", .display),
        ("robot", .toy),
        ("bloodpressure", .health), ("thermometer", .health), ("glucose", .health),
        ("heartrate", .health), ("pulse", .health), ("scale", .health),
        ("phone", .phone),
        ("computer", .computer),
        ("audio", .audio),
        ("peripheral", .peripheral), ("input", .peripheral),
        ("imaging", .imaging),
    ]

    // MARK: Major wording (fallback; macOS 26 no longer reports it)

    private static let majorKindsByWording: [String: BluetoothDeviceKind] = [
        "computer": .computer,
        "phone": .phone,
        "audio": .audio,
        "audiovideo": .audio,
        "peripheral": .peripheral,
        "input": .peripheral,
        "imaging": .imaging,
        "toy": .toy,
        "health": .health,
    ]

    private static let majorContainsRules: [(token: String, kind: BluetoothDeviceKind)] = [
        ("computer", .computer), ("phone", .phone), ("audio", .audio),
        ("peripheral", .peripheral), ("input", .peripheral), ("imaging", .imaging),
        ("toy", .toy), ("health", .health),
    ]
}
