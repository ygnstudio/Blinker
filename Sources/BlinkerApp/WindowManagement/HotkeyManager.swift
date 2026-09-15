import AppKit
import BlinkerCore
import Carbon.HIToolbox
import os

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
    private static let hoverToggleStorageKey = "com.ygnstudio.blinker.hover-toggle-hotkey"
    private static let hotkeySignature = OSType(0x424C_4E4B) // 'BLNK'
    /// Reserved hot key id for the hover-overlay toggle command; far outside
    /// the window-action id range (table index + 1).
    private static let hoverToggleHotKeyID: UInt32 = 0x484F // 'HO'

    /// The default hover-toggle combo shipped on first launch.
    private static let defaultHoverToggleCombo = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_H),
        modifiers: UInt32(controlKey | optionKey)
    )

    /// What the recorder is currently capturing, if anything.
    enum RecordingTarget: Equatable {
        case windowAction(ButtonAction)
        case hoverToggle
    }

    /// The combo that toggles hover enlargement from anywhere; `nil` disables
    /// the command hotkey. `nil` is persisted (encoded as JSON `null`) so a
    /// cleared binding survives relaunches.
    @Published private(set) var hoverToggleCombo: HotkeyCombo? {
        didSet { persistHoverToggleCombo() }
    }

    /// Invoked when the hover-toggle hotkey fires; wired to the app
    /// delegate, which flips `HoverOverlaySettings.isEnabled`.
    var onToggleHoverOverlay: (() -> Void)?

    @Published private(set) var bindings: [String: HotkeyCombo] {
        didSet { persist() }
    }

    @Published private(set) var isEnabled: Bool {
        didSet { persistEnabled() }
    }

    /// The command currently waiting for a key press in the recorder, if
    /// any. One recorder target at a time; `endRecording()` cancels it.
    @Published private(set) var recordingTarget: RecordingTarget?

    /// Inline feedback shown while the recorder rejects a key press (e.g. a
    /// bare key without modifiers); cleared on the next valid press.
    @Published private(set) var recordingHint: String?

    private var registeredHotKeys: [String: EventHotKeyRef?] = [:]
    private var registeredHoverToggleHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?
    private let frontWindowPerformer: FrontWindowActionPerformer
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "hotkeys")

    init(frontWindowPerformer: FrontWindowActionPerformer, defaults: UserDefaults = .standard) {
        self.frontWindowPerformer = frontWindowPerformer
        self.defaults = defaults

        if defaults.object(forKey: Self.enabledKey) == nil {
            // First launch: ship the default scheme. Assignments in init do
            // not fire the didSet observers, so persist everything here
            // explicitly — otherwise `enabledKey` never lands in defaults,
            // every subsequent launch takes this branch again and wipes the
            // user's customizations.
            isEnabled = true
            bindings = Self.defaultBindings
            hoverToggleCombo = Self.defaultHoverToggleCombo
            defaults.set(true, forKey: Self.enabledKey)
            if let data = try? JSONEncoder().encode(bindings) {
                defaults.set(data, forKey: Self.storageKey)
            }
            if let data = try? JSONEncoder().encode(hoverToggleCombo) {
                defaults.set(data, forKey: Self.hoverToggleStorageKey)
            }
        } else {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
            if let data = defaults.data(forKey: Self.storageKey) {
                bindings = (try? JSONDecoder().decode([String: HotkeyCombo].self, from: data)) ?? [:]
            } else {
                bindings = [:]
            }
            // A stored JSON `null` decodes as `nil` — an explicitly cleared
            // binding stays cleared; a missing key means "never configured"
            // and falls back to the shipped default.
            if let data = defaults.data(forKey: Self.hoverToggleStorageKey),
               let decoded = try? JSONDecoder().decode(HotkeyCombo?.self, from: data) {
                hoverToggleCombo = decoded
            } else {
                hoverToggleCombo = Self.defaultHoverToggleCombo
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
    /// Esc cancels; a key with at least one modifier records; a bare key
    /// keeps the recorder waiting with an inline hint.
    func beginRecording(for action: ButtonAction) {
        recordNextKey(target: .windowAction(action))
    }

    /// Starts capturing the next key press as the hover-toggle binding;
    /// same rules as the window-action recorder.
    func beginRecordingHoverToggle() {
        recordNextKey(target: .hoverToggle)
    }

    /// Cancels any in-flight recording. Also called when the settings UI
    /// goes away, so the local monitor can never outlive its row.
    func endRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        recordingTarget = nil
        recordingHint = nil
    }

    /// The single recorder both binding kinds share: one local key monitor,
    /// one set of rules, one dispatch on completion.
    private func recordNextKey(target: RecordingTarget) {
        endRecording()
        recordingTarget = target
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handleRecordingKeyEvent(event) ? nil : event
        }
    }

    /// Consumes one key press while recording. Returns `true` when the event
    /// was swallowed (it resolved, canceled or was rejected by the
    /// recorder); `false` lets it propagate — only bare Tab does, so
    /// keyboard navigation out of the recorder keeps working.
    private func handleRecordingKeyEvent(_ event: NSEvent) -> Bool {
        guard let target = recordingTarget else { return false }

        // Esc cancels the recording (and is swallowed so it cannot close the
        // settings window underneath).
        if event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            return true
        }

        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)

        // Bare Tab stays usable for focus navigation while recording.
        if carbonModifiers == 0, event.keyCode == UInt16(kVK_Tab) {
            return false
        }

        guard carbonModifiers != 0 else {
            // A key without modifiers cannot be a global hotkey (it would
            // shadow normal typing everywhere); keep recording and explain.
            recordingHint = tr(
                "需按住至少一个修饰键（⌘ ⌥ ⌃ ⇧）",
                "Hold at least one modifier key (⌘ ⌥ ⌃ ⇧)"
            )
            return true
        }

        endRecording()
        let combo = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        switch target {
        case .windowAction(let action):
            bind(combo, for: action)
        case .hoverToggle:
            bindHoverToggle(combo)
        }
        return true
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
        // The reserved command id dispatches to the app command; otherwise
        // the hot key id encodes the binding table index (see register).
        if hotKeyID.id == Self.hoverToggleHotKeyID {
            logger.info("hotkey fired: toggle hover overlay")
            onToggleHoverOverlay?()
            return
        }
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
        if let combo = hoverToggleCombo {
            registerHoverToggle(combo)
        }
    }

    private func unregisterAll() {
        for (_, ref) in registeredHotKeys {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        registeredHotKeys.removeAll()
        if let ref = registeredHoverToggleHotKey {
            UnregisterEventHotKey(ref)
        }
        registeredHoverToggleHotKey = nil
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

// MARK: - Modifier mapping & conflict warnings

extension HotkeyManager {
    /// Maps AppKit modifier flags onto Carbon's modifier mask.
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

    /// Warns when `combo` is already bound to another Blinker command —
    /// Carbon would register both but only ever deliver one of them, leaving
    /// the other silently dead. Pass `action: nil` when recording the hover
    /// toggle; its own current binding is then exempt.
    func internalConflictWarning(for combo: HotkeyCombo, action: ButtonAction?) -> String? {
        for other in Self.bindableActions where other != action {
            if bindings[other.rawValue] == combo {
                return tr(
                    "已用于「\(other.localizedLabel)」",
                    "Already used by \"\(other.localizedLabel)\""
                )
            }
        }
        if action != nil, hoverToggleCombo == combo {
            return tr("已用于「悬停放大开关」", "Already used by the hover toggle")
        }
        return nil
    }
}

// MARK: - Hover-toggle command hotkey

/// The hover-enlargement toggle lives outside the window-action table: it
/// dispatches through a reserved hot key id and a callback wired by the app
/// delegate instead of `FrontWindowActionPerformer`. Recording goes through
/// the shared `recordNextKey` path.
extension HotkeyManager {
    func bindHoverToggle(_ combo: HotkeyCombo) {
        hoverToggleCombo = combo
        registerHoverToggle(combo)
    }

    func clearHoverToggleBinding() {
        hoverToggleCombo = nil
        if let ref = registeredHoverToggleHotKey {
            UnregisterEventHotKey(ref)
        }
        registeredHoverToggleHotKey = nil
    }

    private func registerHoverToggle(_ combo: HotkeyCombo) {
        if let existing = registeredHoverToggleHotKey {
            UnregisterEventHotKey(existing)
        }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotkeySignature, id: Self.hoverToggleHotKeyID)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            registeredHoverToggleHotKey = hotKeyRef
        } else {
            logger.error("RegisterEventHotKey failed for hover toggle: \(status)")
            registeredHoverToggleHotKey = nil
        }
    }

    private func persistHoverToggleCombo() {
        // Encodes `nil` as JSON `null`, so an explicitly cleared binding is
        // distinguishable from "never stored" on the next launch.
        if let data = try? JSONEncoder().encode(hoverToggleCombo) {
            defaults.set(data, forKey: Self.hoverToggleStorageKey)
        } else {
            defaults.removeObject(forKey: Self.hoverToggleStorageKey)
        }
    }
}
