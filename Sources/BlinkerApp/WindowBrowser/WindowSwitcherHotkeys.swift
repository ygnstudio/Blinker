import AppKit
import Carbon.HIToolbox

/// Carbon owns only Option-Tab. Keyboard handling inside the panel is local;
/// modifier-release observation never consumes normal typing in other apps.
final class WindowSwitcherHotkeys {
    var onCycle: ((Int) -> Void)?
    var onRelease: (() -> Void)?
    private var handler: EventHandlerRef?
    private var hotkeys: [EventHotKeyRef] = []
    private var modifierMonitor: Any?
    private static let signature = OSType(0x4257_5357)

    func start() -> Bool {
        stop()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                              nil, &identity)
            guard identity.signature == WindowSwitcherHotkeys.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<WindowSwitcherHotkeys>.fromOpaque(context).takeUnretainedValue()
            owner.onCycle?(identity.id == 1 ? 1 : -1)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { stop(); return false }
        for (index, flags) in [optionKey, optionKey | shiftKey].enumerated() {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(flags),
                                             EventHotKeyID(signature: Self.signature, id: UInt32(index + 1)),
                                             GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { stop(); return false }
            hotkeys.append(reference)
        }
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.option) {
                self?.onRelease?()
            }
        }
        return true
    }

    func stop() {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        hotkeys = []
        if let handler {
            RemoveEventHandler(handler)
        }
        handler = nil
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
        }
        modifierMonitor = nil
    }

    deinit { stop() }
}
