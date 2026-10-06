import AppKit
import BlinkerCore

/// Full-screen overlays for display and keyboard cleaning. Keyboard locking
/// uses a system event tap (KeyboardInputLock): window-level capture never
/// receives keystrokes unless this app is active, which a menu-bar app cannot
/// guarantee. Global hotkeys keep working in display mode without a tap;
/// keyboard mode requires Accessibility + Input Monitoring and refuses to
/// enter a lock it cannot actually enforce.
@MainActor
final class CleaningWindowController {
    enum Mode {
        /// Black screens for wiping the display; Esc or a click exits.
        case display
        /// Locked screen for wiping the keyboard; the on-screen button or
        /// Escape ×3 exits, so stray keystrokes cannot end the session.
        case keyboard
    }

    /// Both permissions the keyboard lock needs; injectable for tests.
    var keyboardLockGate: () -> Bool = {
        AccessibilityPermission.isTrusted && InputMonitoringPermission.isGranted
    }
    /// Fired when keyboard cleaning cannot start because the gate fails or
    /// tap creation is denied (stale grant needing a relaunch).
    var onKeyboardLockPermissionMissing: (() -> Void)?

    /// Windows are kept alive for the whole app lifetime and reused. AppKit's
    /// transform animation (`_NSWindowTransformAnimation`) only releases its
    /// window reference when the CA transaction commits, which can happen long
    /// after `stop()` returns; deallocating the window any earlier crashed in
    /// the commit's autorelease drain (EXC_BAD_ACCESS in
    /// `-[_NSWindowTransformAnimation dealloc]` → objc_release). Retired
    /// windows (screen-set changes) stay referenced for the same reason — a
    /// deliberate, tiny leak over a crash.
    private var windows: [NSWindow] = []
    private var retiredWindows: [NSWindow] = []
    private var inputLock: KeyboardInputLock?
    private(set) var isActive = false

    func start(_ mode: Mode) {
        guard !isActive, !NSScreen.screens.isEmpty else { return }
        if mode == .keyboard, !keyboardLockGate() {
            onKeyboardLockPermissionMissing?()
            return
        }
        var lock: KeyboardInputLock?
        if mode == .keyboard || keyboardLockGate() {
            let candidate = KeyboardInputLock()
            let lockMode: KeyboardInputLock.Mode = mode == .keyboard ? .keyboard : .display
            let started = candidate.start(mode: lockMode) { [weak self] in
                Task { @MainActor in self?.stop() }
            }
            if mode == .keyboard, !started {
                // Gate passed but the tap was denied: the grant predates this
                // binary and only applies after relaunch (upstream Cleankey
                // names the same failure).
                onKeyboardLockPermissionMissing?()
                return
            }
            lock = started ? candidate : nil
        }
        isActive = true
        inputLock = lock
        NSApp.activate(ignoringOtherApps: true)
        if reusableWindows(for: mode) {
            windows.forEach { ($0.contentView as? CleaningView)?.resetForReuse() }
        } else {
            retiredWindows.append(contentsOf: windows)
            windows = NSScreen.screens.map { screen in
                CleaningWindow(screen: screen, mode: mode) { [weak self] in
                    Task { @MainActor in self?.stop() }
                }
            }
        }
        windows.forEach { $0.orderFrontRegardless() }
        if let key = windows.first {
            key.makeKey()
            key.makeFirstResponder(key.contentView)
        }
        if mode == .display {
            NSCursor.hide()
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        inputLock?.stop()
        inputLock = nil
        NSCursor.unhide()
        // orderOut only — never close(), never drop the reference. See the
        // comment on `windows` above.
        windows.forEach { $0.orderOut(nil) }
    }

    /// Existing windows are reusable when they were built for the same mode
    /// and cover exactly the current screens (count and frames).
    private func reusableWindows(for mode: Mode) -> Bool {
        let screens = NSScreen.screens
        guard windows.count == screens.count,
              windows.allSatisfy({ ($0 as? CleaningWindow)?.windowMode == mode })
        else { return false }
        let windowFrames = windows.map { NSStringFromRect($0.frame) }.sorted()
        let screenFrames = screens.map { NSStringFromRect($0.frame) }.sorted()
        return windowFrames == screenFrames
    }
}

/// Borderless window covering one screen. Key capture lives here, at the
/// window level: a first responder further down the chain could change, but
/// the menu bar ⌘Q must stay unreachable for the whole session.
private final class CleaningWindow: NSWindow {
    let windowMode: CleaningWindowController.Mode
    private let onExit: () -> Void

    init(screen: NSScreen, mode: CleaningWindowController.Mode, onExit: @escaping () -> Void) {
        self.windowMode = mode
        self.onExit = onExit
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        // The controller owns the lifetime; close() must never release the
        // window underneath an in-flight AppKit animation (upstream Duo does
        // the same for its overlay).
        isReleasedWhenClosed = false
        contentView = CleaningView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                   mode: mode, onExit: onExit)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Swallows every chord before the main menu can match it (⌘Q included).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if windowMode == .display, event.keyCode == 53,
           event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) {
            onExit()
        }
        return true
    }

    /// Plain keys die here too; display mode only lets Esc out.
    override func keyDown(with event: NSEvent) {
        if windowMode == .display, event.keyCode == 53, !event.isARepeat {
            onExit()
        }
    }
}

/// Swallows every keystroke and command chord. Display mode lets Esc and
/// clicks through to the exit handler; keyboard mode only trusts the mouse
/// on the exit button.
private final class CleaningView: NSView {
    private let mode: CleaningWindowController.Mode
    private let onExit: () -> Void
    private var hintLabel: NSTextField?
    private var hintFadeGeneration = 0

    init(frame: NSRect, mode: CleaningWindowController.Mode, onExit: @escaping () -> Void) {
        self.mode = mode
        self.onExit = onExit
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = (mode == .display
            ? NSColor.black
            : NSColor(calibratedWhite: 0.08, alpha: 1)).cgColor
        if mode == .keyboard {
            buildLockUI()
        } else {
            buildFadingHint()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if mode == .display, event.keyCode == 53, !event.isARepeat {
            onExit()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if mode == .display, event.keyCode == 53,
           event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) {
            onExit()
        }
        return true
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .display {
            onExit()
        }
    }

    /// Centered lock message and the mouse-only exit button (no key
    /// equivalent, deliberately).
    private func buildLockUI() {
        let symbol = NSImageView(image: NSImage(systemSymbolName: "keyboard",
                                                accessibilityDescription: nil) ?? NSImage())
        symbol.symbolConfiguration = .init(pointSize: 40, weight: .regular)
        symbol.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: String(
            localized: "键盘已锁定", comment: "keyboard cleaning lock title"))
        title.font = .systemFont(ofSize: 20, weight: .medium)
        title.textColor = .white
        let caption = NSTextField(wrappingLabelWithString: String(
            localized: "按键与媒体键已被系统级拦截，Touch ID 与电源键除外",
            comment: "keyboard cleaning scope note"))
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2
        caption.alignment = .center
        let escapeHint = NSTextField(wrappingLabelWithString: String(
            localized: "连按三次 Esc 也可退出",
            comment: "keyboard cleaning emergency escape hint"))
        escapeHint.font = .systemFont(ofSize: 12)
        escapeHint.textColor = .secondaryLabelColor
        escapeHint.alignment = .center
        let exit = NSButton(title: String(localized: "退出键盘清洁", comment: "exit button"),
                            target: self, action: #selector(exitClicked))
        exit.bezelStyle = .rounded
        exit.controlSize = .large
        exit.keyEquivalent = ""
        let stack = NSStackView(views: [symbol, title, caption, escapeHint, exit])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(22, after: escapeHint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -80),
        ])
    }

    /// Restores the display-mode hint for a reused window; a stale fade from
    /// the previous session is cancelled via the generation counter.
    func resetForReuse() {
        guard let hint = hintLabel else { return }
        hint.layer?.removeAllAnimations()
        hint.alphaValue = 1
        scheduleHintFade()
    }

    /// A faint exit hint that fades out so the black screen stays clean.
    private func buildFadingHint() {
        let hint = NSTextField(labelWithString: String(
            localized: "按 Esc 或点击退出", comment: "display cleaning exit hint"))
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = NSColor.white.withAlphaComponent(0.55)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
        ])
        hintLabel = hint
        scheduleHintFade()
    }

    private func scheduleHintFade() {
        hintFadeGeneration += 1
        let generation = hintFadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak hintLabel] in
            guard let self, self.hintFadeGeneration == generation else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.8
                hintLabel?.animator().alphaValue = 0
            }
        }
    }

    @objc private func exitClicked() {
        onExit()
    }
}
