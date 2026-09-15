import Carbon.HIToolbox

/// A recorded global hotkey: a Carbon virtual key code plus Carbon modifier
/// flags, persisted in `UserDefaults`.
struct HotkeyCombo: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Human-readable label, e.g. "⌃⌥←" or "⌘⇧K".
    var displayLabel: String {
        var label = ""
        if modifiers & UInt32(controlKey) != 0 {
            label += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            label += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            label += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            label += "⌘"
        }
        label += Self.keyName(for: keyCode)
        return label
    }

    /// Readable names for the key codes users actually bind; everything else
    /// falls back to "Key N".
    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Space: tr("空格", "Space")
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case _ where isLetter(keyCode): letterName(keyCode)
        case _ where isDigit(keyCode): digitName(keyCode)
        default: "Key \(keyCode)"
        }
    }

    /// Letters are scattered across the key-code table; map each explicitly.
    private static let letterTable: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
    ]

    private static let digitTable: [Int: String] = [
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]

    private static func isLetter(_ keyCode: UInt32) -> Bool {
        letterTable[Int(keyCode)] != nil
    }

    private static func isDigit(_ keyCode: UInt32) -> Bool {
        digitTable[Int(keyCode)] != nil
    }

    private static func letterName(_ keyCode: UInt32) -> String {
        letterTable[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static func digitName(_ keyCode: UInt32) -> String {
        digitTable[Int(keyCode)] ?? "Key \(keyCode)"
    }
}
