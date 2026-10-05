import Foundation

extension MenuBarConfiguration.Placement {
    var title: String {
        switch self {
        case .menuBar: String(localized: "仅菜单栏")
        case .dock: String(localized: "仅 Dock")
        case .both: String(localized: "菜单栏与 Dock")
        }
    }
}

extension MenuBarConfiguration.DockBackground {
    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "浅色")
        case .dark: String(localized: "深色")
        case .transparent: String(localized: "透明")
        }
    }
}

extension MenuBarConfiguration.Stroke {
    var title: String {
        switch self {
        case .light: String(localized: "细")
        case .regular: String(localized: "标准")
        case .bold: String(localized: "粗")
        }
    }
}

extension MenuBarConfiguration.VolumeStyle {
    var title: String {
        switch self {
        case .dots: String(localized: "圆点")
        case .arc: String(localized: "弧线")
        }
    }
}

extension MenuBarConfiguration.ClickAction {
    var title: String {
        switch self {
        case .panel: String(localized: "状态面板")
        case .rules: String(localized: "应用规则")
        }
    }
}

extension MenuBarConfiguration.ScrollScope {
    var title: String {
        switch self {
        case .panel: String(localized: "整个状态面板")
        case .volumeControl: String(localized: "仅音量控件")
        }
    }
}

extension MenuBarConfiguration.ScrollDirection {
    var title: String {
        switch self {
        case .upward: String(localized: "向上")
        case .down: String(localized: "向下")
        }
    }
}

extension MenuBarConfiguration.Section {
    var title: String {
        switch self {
        case .battery: String(localized: "电池")
        case .network: String(localized: "网络")
        case .volume: String(localized: "音量")
        case .bluetooth: String(localized: "蓝牙")
        }
    }
}
