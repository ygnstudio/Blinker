import Carbon.HIToolbox

/// Thin Carbon adapter. Tests inject a driver at the same result/cleanup boundary.
final class CarbonHotkeyDriver: HotkeyRegistrationDriving {
    private let signature: OSType
    private var handler: EventHandlerRef?
    private var references: [String: EventHotKeyRef] = [:]
    private var onPress: ((UInt32) -> Void)?

    init(signature: UInt32) {
        self.signature = signature
    }

    func installHandler(onPress: @escaping (UInt32) -> Void) -> Int32 {
        if handler != nil {
            return noErr
        }
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<CarbonHotkeyDriver>.fromOpaque(context).takeUnretainedValue()
            var identity = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard result == noErr, identity.signature == owner.signature else {
                return OSStatus(eventNotHandledErr)
            }
            owner.onPress?(identity.id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr, handler != nil else {
            removeHandler()
            return status == noErr ? Int32(paramErr) : status
        }
        return noErr
    }

    func register(_ binding: GlobalHotkeyBinding) -> Int32 {
        unregister(binding.key)
        var reference: EventHotKeyRef?
        // Shared registrations can succeed while another app suppresses delivery,
        // or dispatch to both apps. Exclusive registration makes conflicts explicit.
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
                                         EventHotKeyID(signature: signature, id: binding.id),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive),
                                         &reference)
        guard status == noErr, let reference else {
            if let reference {
                UnregisterEventHotKey(reference)
            }
            return status == noErr ? Int32(paramErr) : status
        }
        references[binding.key] = reference
        return noErr
    }

    func unregister(_ key: String) {
        if let reference = references.removeValue(forKey: key) {
            UnregisterEventHotKey(reference)
        }
    }

    func removeHandler() {
        if let handler {
            RemoveEventHandler(handler)
        }
        handler = nil
        onPress = nil
    }

    deinit {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        removeHandler()
    }
}
