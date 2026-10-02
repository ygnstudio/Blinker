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
        .restorePreviousFrame, .tileFirstThird, .tileCenterThird, .tileLastThird,
        .tileFirstTwoThirds, .tileLastTwoThirds,
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

    /// The default hover-toggle combo shipped on first launch.
    private static let defaultHoverToggleCombo = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_H),
        modifiers: UInt32(controlKey | optionKey)
    )

    /// A bindable hotkey slot: either a window action row or the reserved
    /// hover-toggle command. Both the recorder and the Carbon registration
    /// path dispatch on this one enum.
    enum BindingTarget: Equatable {
        case windowAction(ButtonAction)
        case hoverToggle

        /// Stable registration key shared by the ref table.
        var registrationKey: String {
            switch self {
            case let .windowAction(action): action.rawValue
            case .hoverToggle: "hoverToggle"
            }
        }

        /// Stable Carbon hot key id: for window actions, the table index + 1
        /// (0 is reserved); for the hover toggle, a reserved id far outside
        /// that range.
        var hotKeyID: UInt32 {
            switch self {
            case let .windowAction(action):
                UInt32(HotkeyManager.bindableActions.firstIndex(of: action)?.advanced(by: 1) ?? 0)
            case .hoverToggle:
                Self.hoverToggleHotKeyID
            }
        }

        /// Reserved hot key id for the hover-overlay toggle command; far
        /// outside the window-action id range (table index + 1).
        fileprivate static let hoverToggleHotKeyID: UInt32 = 0x484F // 'HO'
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
    @Published private(set) var recordingTarget: BindingTarget?

    /// Inline feedback shown while the recorder rejects a key press (e.g. a
    /// bare key without modifiers); cleared on the next valid press.
    @Published private(set) var recordingHint: String?

    private var sessionPaused = false
    @Published private(set) var registrationFailures: [String: GlobalHotkeyRegistry.Failure] = [:]
    private let registry = GlobalHotkeyRegistry(signature: hotkeySignature)
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
            storeEncoded(bindings, forKey: Self.storageKey, in: defaults, category: "hotkeys")
            storeEncoded(
                hoverToggleCombo,
                forKey: Self.hoverToggleStorageKey,
                in: defaults,
                category: "hotkeys"
            )
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

        registry.onPress = { [weak self] in self?.handleHotKeyID($0) }
        reregisterAll()
    }

    // MARK: - Mutation (settings UI)

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        reregisterAll()
    }

    func bind(_ combo: HotkeyCombo, for action: ButtonAction) {
        bindings[action.rawValue] = combo
        reregisterAll()
    }

    func clearBinding(for action: ButtonAction) {
        bindings[action.rawValue] = nil
        reregisterAll()
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
    private func recordNextKey(target: BindingTarget) {
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
            recordingHint = String(localized: "需按住至少一个修饰键（⌘ ⌥ ⌃ ⇧）")
            return true
        }

        endRecording()
        let combo = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        switch target {
        case let .windowAction(action):
            bind(combo, for: action)
        case .hoverToggle:
            bindHoverToggle(combo)
        }
        return true
    }

    // MARK: - Registration

    private func handleHotKeyID(_ identity: UInt32) {
        if identity == BindingTarget.hoverToggleHotKeyID {
            logger.info("hotkey fired: toggle hover overlay")
            onToggleHoverOverlay?()
            return
        }
        guard let action = Self.bindableActions.first(where: {
            BindingTarget.windowAction($0).hotKeyID == identity
        }) else { return }
        logger.info("hotkey fired: \(action.rawValue, privacy: .public)")
        frontWindowPerformer.perform(action)
    }

    func setSessionPaused(_ paused: Bool) {
        sessionPaused = paused
        reregisterAll()
    }

    func retryRegistration(for target: BindingTarget) {
        registry.retry(target.registrationKey)
        registrationFailures = registry.failures
    }

    func registrationWarning(for target: BindingTarget) -> String? {
        guard let failure = registrationFailures[target.registrationKey] else { return nil }
        switch failure {
        case let .handler(status):
            return String(localized: "无法启用快捷键监听（错误 \(Int(status))）。请重试。")
        case .registration(Int32(eventHotKeyExistsErr)):
            return String(localized: "快捷键被占用。关闭冲突应用或更换组合后重试。")
        case let .registration(status):
            return String(localized: "快捷键注册失败（错误 \(Int(status))）。请重试或更换组合。")
        }
    }

    private func reregisterAll() {
        var requested = Self.bindableActions.compactMap { action -> GlobalHotkeyBinding? in
            guard let combo = bindings[action.rawValue] else { return nil }
            return registration(combo, target: .windowAction(action))
        }
        if let combo = hoverToggleCombo {
            requested.append(registration(combo, target: .hoverToggle))
        }
        registry.update(requested, enabled: isEnabled, paused: sessionPaused)
        registrationFailures = registry.failures
    }

    private func registration(_ combo: HotkeyCombo, target: BindingTarget) -> GlobalHotkeyBinding {
        GlobalHotkeyBinding(key: target.registrationKey, id: target.hotKeyID,
                            keyCode: combo.keyCode, modifiers: combo.modifiers)
    }

    // MARK: - Persistence

    private func persist() {
        storeEncoded(bindings, forKey: Self.storageKey, in: defaults, category: "hotkeys")
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
            HotkeyCombo(
                keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)
            ): String(localized: "输入法切换"),
            HotkeyCombo(
                keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey)
            ): String(localized: "调度中心"),
            HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)
            ): String(localized: "截屏"),
            HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)
            ): String(localized: "截屏"),
            HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)
            ): String(localized: "截屏"),
            HotkeyCombo(
                keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey | optionKey)
            ): String(localized: "强制退出"),
        ]
        guard let name = conflicts[combo] else { return nil }
        return String(localized: "与系统快捷键冲突：") + name
    }

    /// Warns when `combo` is already bound to another Blinker command —
    /// Carbon would register both but only ever deliver one of them, leaving
    /// the other silently dead. Pass `action: nil` when recording the hover
    /// toggle; its own current binding is then exempt.
    func internalConflictWarning(for combo: HotkeyCombo, action: ButtonAction?) -> String? {
        for other in Self.bindableActions where other != action {
            if bindings[other.rawValue] == combo {
                return String(localized: "已用于「\(other.localizedLabel)」")
            }
        }
        if action != nil, hoverToggleCombo == combo {
            return String(localized: "已用于「悬停放大开关」")
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
        reregisterAll()
    }

    func clearHoverToggleBinding() {
        hoverToggleCombo = nil
        reregisterAll()
    }

    private func persistHoverToggleCombo() {
        // Encodes `nil` as JSON `null`, so an explicitly cleared binding is
        // distinguishable from "never stored" on the next launch.
        storeEncoded(hoverToggleCombo, forKey: Self.hoverToggleStorageKey, in: defaults, category: "hotkeys")
    }
}
