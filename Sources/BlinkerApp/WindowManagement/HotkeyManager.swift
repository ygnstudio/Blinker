import AppKit
import BlinkerCore
import Carbon.HIToolbox
import os

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

/// Registers and manages the global hotkeys that trigger window actions on
/// the frontmost window. Bindings are persisted per action; a master switch
/// enables or disables the whole feature.
final class HotkeyManager: ObservableObject {
    /// The actions users can bind, in display order.
    static let bindableActions: [ButtonAction] = [
        .tileLeft, .tileRight, .tileTop, .tileBottom,
        .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight,
        .maximize, .almostMaximize, .centerWindow, .moveToNextDisplay,
    ]

    /// The scheme shipped on first launch: ⌃⌥ plus arrows and corner keys.
    private static let defaultBindings: [String: HotkeyCombo] = [
        ButtonAction.tileLeft.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.tileRight.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.maximize.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.almostMaximize.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.tileTopLeft.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_U),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.tileTopRight.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_I),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.tileBottomLeft.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.tileBottomRight.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey)
        ),
        ButtonAction.centerWindow.rawValue: HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey)
        ),
    ]

    private static let storageKey = "com.ygnstudio.blinker.hotkeys"
    private static let enabledKey = "com.ygnstudio.blinker.hotkeysEnabled"
    private static let hotkeySignature = OSType(0x424C_4E4B) // 'BLNK'

    @Published private(set) var bindings: [String: HotkeyCombo] {
        didSet { persist() }
    }

    @Published private(set) var isEnabled: Bool {
        didSet { persistEnabled() }
    }

    /// The action currently waiting for a key press in the recorder, if any.
    @Published private(set) var recordingAction: ButtonAction?

    private var registeredHotKeys: [String: EventHotKeyRef?] = [:]
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?
    private let frontWindowPerformer: FrontWindowActionPerformer
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "hotkeys")

    init(frontWindowPerformer: FrontWindowActionPerformer, defaults: UserDefaults = .standard) {
        self.frontWindowPerformer = frontWindowPerformer
        self.defaults = defaults

        if defaults.object(forKey: Self.enabledKey) == nil {
            // First launch: ship the default scheme.
            isEnabled = true
            bindings = Self.defaultBindings
        } else {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
            if let data = defaults.data(forKey: Self.storageKey) {
                bindings = (try? JSONDecoder().decode([String: HotkeyCombo].self, from: data)) ?? [:]
            } else {
                bindings = [:]
            }
        }

        installEventHandler()
        reregisterAll()
    }

    // MARK: - Mutation (settings UI)

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            reregisterAll()
        } else {
            unregisterAll()
        }
    }

    func bind(_ combo: HotkeyCombo, for action: ButtonAction) {
        bindings[action.rawValue] = combo
        register(combo, for: action)
    }

    func clearBinding(for action: ButtonAction) {
        bindings[action.rawValue] = nil
        if let ref = registeredHotKeys.removeValue(forKey: action.rawValue), let ref {
            UnregisterEventHotKey(ref)
        }
    }

    // MARK: - Recording

    /// Starts capturing the next key press as the new binding for `action`.
    /// Escape cancels; any other key (with at least one modifier) records.
    func beginRecording(for action: ButtonAction) {
        endRecording()
        recordingAction = action
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordingEvent(event)
            return nil
        }
    }

    func endRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        recordingAction = nil
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        guard let action = recordingAction else {
            endRecording()
            return
        }
        endRecording()
        guard event.keyCode != UInt16(kVK_Escape) else { return }

        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else { return } // require at least one modifier
        bind(HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers), for: action)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) {
            carbon |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            carbon |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbon |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbon |= UInt32(shiftKey)
        }
        return carbon
    }

    /// Warns when a combo collides with a well-known system shortcut.
    static func systemConflictWarning(for combo: HotkeyCombo) -> String? {
        let conflicts: [HotkeyCombo: String] = [
            HotkeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)): "Spotlight",
            HotkeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)): tr(
                "输入法切换",
                "Input Source"
            ),
            HotkeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey)): tr(
                "调度中心",
                "Mission Control"
            ),
            HotkeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)): tr(
                "截屏",
                "Screenshot"
            ),
            HotkeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)): tr(
                "截屏",
                "Screenshot"
            ),
            HotkeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)): tr(
                "截屏",
                "Screenshot"
            ),
            HotkeyCombo(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey | optionKey)): tr(
                "强制退出",
                "Force Quit"
            ),
        ]
        guard let name = conflicts[combo] else { return nil }
        return tr("与系统快捷键冲突：", "Conflicts with a system shortcut: ") + name
    }

    // MARK: - Registration (Carbon)

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
        if status != noErr {
            logger.error("InstallEventHandler failed: \(status)")
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return }
        // The hot key id encodes the binding table index (see register).
        guard let action = Self.bindableActions.first(where: { id(for: $0) == hotKeyID.id }) else { return }
        logger.info("hotkey fired: \(action.rawValue, privacy: .public)")
        frontWindowPerformer.perform(action)
    }

    /// Stable per-action hot key id: table index + 1 (0 is reserved).
    private func id(for action: ButtonAction) -> UInt32 {
        UInt32(Self.bindableActions.firstIndex(of: action)?.advanced(by: 1) ?? 0)
    }

    private func register(_ combo: HotkeyCombo, for action: ButtonAction) {
        if let existing = registeredHotKeys[action.rawValue], let existing {
            UnregisterEventHotKey(existing)
        }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotkeySignature, id: id(for: action))
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            registeredHotKeys[action.rawValue] = hotKeyRef
        } else {
            logger.error("RegisterEventHotKey failed for \(action.rawValue, privacy: .public): \(status)")
            registeredHotKeys[action.rawValue] = nil
        }
    }

    private func reregisterAll() {
        guard isEnabled else { return }
        for action in Self.bindableActions {
            guard let combo = bindings[action.rawValue] else { continue }
            register(combo, for: action)
        }
    }

    private func unregisterAll() {
        for (_, ref) in registeredHotKeys {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        registeredHotKeys.removeAll()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func persistEnabled() {
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }
}
