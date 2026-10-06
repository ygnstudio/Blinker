/// Pure decision layer for the keyboard-lock event tap: which raw CGEvent
/// types the tap observes, and which of those it swallows. Kept free of event
/// objects so the policy is unit-testable (upstream Cleankey uses the same
/// mask and the same media-key carve-out).
public enum KeyboardSwallow {
    /// Raw value of CGEventType.keyDown.
    public static let keyDownType: UInt32 = 10
    /// Raw value of CGEventType.keyUp.
    public static let keyUpType: UInt32 = 11
    /// Raw value of CGEventType.flagsChanged.
    public static let flagsChangedType: UInt32 = 12
    /// NX_SYSDEFINED / NSEvent.EventType.systemDefined — carries the media
    /// keys (play/pause, brightness, volume). CGEventType has no case for it.
    public static let systemDefinedType: UInt32 = 14
    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS — the system-defined subtype used by
    /// media keys; other system-defined events pass through. Matches the raw
    /// type of NSEvent.EventTypeSubtype.
    public static let auxControlSubtype: Int16 = 8

    /// Event types the tap installs for: keyboard events plus systemDefined
    /// (so media keys can be filtered by subtype).
    public static func handles(_ eventType: UInt32) -> Bool {
        eventType == keyDownType || eventType == keyUpType
            || eventType == flagsChangedType || eventType == systemDefinedType
    }

    /// Whether an observed event is swallowed. All keyboard events are; among
    /// system-defined events only media keys are, the rest pass through.
    public static func swallows(eventType: UInt32, isMediaKeySubtype: Bool) -> Bool {
        guard handles(eventType) else { return false }
        return eventType == systemDefinedType ? isMediaKeySubtype : true
    }
}
