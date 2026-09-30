import BlinkerCore
import SwiftUI

/// Shared menu content for each traffic-light click variant.
enum RuleActionOptions {
    struct Group {
        let label: String?
        let options: [ButtonAction?]
    }

    static let groups: [Group] = [
        Group(label: nil, options: [nil]),
        Group(
            label: String(localized: "窗口"),
            options: [
                .closeWindow, .minimize, .maximize, .almostMaximize,
                .fullscreen, .centerWindow, .moveToNextDisplay, .restorePreviousFrame,
            ]
        ),
        Group(
            label: String(localized: "贴靠"),
            options: [
                .tileLeft, .tileRight, .tileTop, .tileBottom,
                .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight,
                .tileFirstThird, .tileCenterThird, .tileLastThird, .tileFirstTwoThirds, .tileLastTwoThirds,
            ]
        ),
        Group(label: String(localized: "应用"), options: [.quitApp, .hideApp]),
        Group(label: nil, options: [ButtonAction.none]),
    ]
}

extension ClickVariant {
    var localizedLabel: String {
        switch self {
        case .left: String(localized: "左键")
        case .right: String(localized: "右键")
        case .optionLeft: String(localized: "⌥+左键")
        case .globeLeft: String(localized: "🌐+左键")
        case .longPressLeft: String(localized: "长按")
        }
    }
}
