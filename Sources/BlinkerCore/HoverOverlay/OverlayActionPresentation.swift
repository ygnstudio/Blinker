import AppKit

struct OverlayActionPresentation: Equatable {
    let action: ButtonAction?

    var label: String {
        action?.localizedLabel ?? String(localized: "此点击方式未配置", bundle: .module)
    }

    var symbol: String {
        action?.extraSymbolName ?? "circle.slash"
    }

    static func resolve(engine: RuleEngine, bundleID: String, button: TrafficButton,
                        variant: ClickVariant) -> Self {
        if let action = engine.action(forBundleIdentifier: bundleID, button: button, variant: variant) {
            return Self(action: action)
        }
        guard variant == .left else { return Self(action: nil) }
        return Self(action: button.nativeAction)
    }

    static func variant(for flags: NSEvent.ModifierFlags) -> ClickVariant {
        flags.contains(.option) ? .optionLeft : flags.contains(.function) ? .globeLeft : .left
    }
}
