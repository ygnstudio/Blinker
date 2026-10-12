import Foundation
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, menuBar, effects, hover, browser, windows, shortcuts, permissions, workspaces

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .workspaces: String(localized: "工作区（实验）")
        case .general: String(localized: "通用")
        case .menuBar: String(localized: "状态图标")
        case .effects: String(localized: "屏幕特效")
        case .permissions: String(localized: "权限与诊断")
        case .hover: String(localized: "悬停按钮")
        case .browser: String(localized: "预览与切换")
        case .windows: String(localized: "布局与桌面")
        case .shortcuts: String(localized: "快捷键")
        }
    }

    var symbol: String {
        switch self {
        case .workspaces: "rectangle.3.group"
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .effects: "macbook"
        case .permissions: "hand.raised"
        case .hover: "arrow.up.left.and.arrow.down.right"
        case .browser: "macwindow.on.rectangle"
        case .windows: "rectangle.split.2x2"
        case .shortcuts: "keyboard"
        }
    }
}

/// Preferences routing never changes the rule window's selection or search.
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsDestination? = .general

    /// Sub-page within the status-icon tab, e.g. deep links from the status panel.
    @Published var menuBarPage: MenuBarSettingsPage = .icon
    @Published var diagnosticBundleID: String?
    @Published var diagnosticRequest = UUID()
    @Published var showsOnboarding = false

    func openDiagnostics(_ appID: String? = nil) {
        diagnosticBundleID = appID
        diagnosticRequest = UUID()
        selection = .permissions
    }
}

enum SettingsSidebarSelection: Hashable {
    case destination(SettingsDestination)
    case menuBar(MenuBarSettingsPage)
}

extension SettingsNavigation {
    var sidebarSelection: SettingsSidebarSelection? {
        get {
            selection == .menuBar ? .menuBar(menuBarPage) : .destination(selection ?? .general)
        }
        set {
            guard let newValue else { return }
            switch newValue {
            case let .destination(destination): selection = destination
            case let .menuBar(page):
                menuBarPage = page
                selection = .menuBar
            }
        }
    }

    var title: String {
        selection == .menuBar ? menuBarPage.title : (selection ?? .general).title
    }
}
