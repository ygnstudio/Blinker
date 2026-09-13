/// A way a traffic button can be clicked. Beyond the plain left click,
/// Blinker also recognizes right clicks, modifier-key clicks and a long
/// press, each of which can carry its own remapped action.
public enum ClickVariant: String, Codable, CaseIterable, Hashable, Sendable {
    /// A plain left click. Actions live in the legacy per-button fields.
    case left
    /// A right click.
    case right
    /// A left click with the Option (⌥) key held down.
    case optionLeft
    /// A left click with the Globe (🌐 / fn) key held down.
    case globeLeft
    /// A left click held down past the long-press threshold.
    case longPressLeft

    /// The slots shown in the rules UI's expanded matrix — every variant
    /// except the plain left click, which owns the three main pickers.
    public static let extraSlots: [ClickVariant] = [
        .right,
        .optionLeft,
        .globeLeft,
        .longPressLeft,
    ]
}
