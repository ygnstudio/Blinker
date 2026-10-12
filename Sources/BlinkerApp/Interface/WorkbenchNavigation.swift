import Combine
import Foundation

/// Stable workspace sections; growing application/device lists stay inside a section.
enum WorkbenchSection: String, CaseIterable, Identifiable {
    case apps, windows, devices, library, system, scenes, tools, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .apps: String(localized: "应用")
        case .windows: String(localized: "窗口")
        case .devices: String(localized: "设备")
        case .library: String(localized: "资料")
        case .system: String(localized: "系统")
        case .scenes: String(localized: "场景")
        case .tools: String(localized: "所有工具")
        case .settings: String(localized: "设置")
        }
    }

    var symbol: String {
        switch self {
        case .apps: "app.dashed"
        case .windows: "macwindow.on.rectangle"
        case .devices: "desktopcomputer"
        case .library: "tray.full"
        case .system: "slider.horizontal.3"
        case .scenes: "rectangle.3.group"
        case .tools: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }
}

/// UI routing only. Existing stores remain the owners of persisted configuration.
@MainActor
final class WorkbenchNavigation: ObservableObject {
    @Published var section: WorkbenchSection = .apps
    @Published private(set) var applicationSearchRequest: UUID?

    private struct SettingsRoute {
        let destination: SettingsDestination
        let menuBarPage: MenuBarSettingsPage
    }

    private var rememberedRoutes: [WorkbenchSection: SettingsRoute] = [:]

    func showApplications() {
        section = .apps
    }

    /// Repeated requests remain observable even when Applications is already open.
    func searchApplications() {
        applicationSearchRequest = UUID()
        section = .apps
    }

    /// Only the latest mounted search field can consume a request. A request
    /// abandoned by another navigation never focuses a hidden page later.
    func consumeApplicationSearchRequest(_ request: UUID) -> Bool {
        guard applicationSearchRequest == request else { return false }
        applicationSearchRequest = nil
        return section == .apps
    }

    /// A menu, diagnostic request or contextual link reveals its existing leaf page.
    func showSettings(using settings: SettingsNavigation) {
        let route = currentRoute(settings)
        let target = Self.section(for: route.destination, menuBarPage: route.menuBarPage)
        rememberedRoutes[target] = route
        section = target
    }

    /// Selecting a top-level section restores its last leaf without changing rule selection.
    func show(_ target: WorkbenchSection, settings: SettingsNavigation) {
        let current = currentRoute(settings)
        let currentSection = Self.section(for: current.destination, menuBarPage: current.menuBarPage)
        rememberedRoutes[currentSection] = current
        if let route = rememberedRoutes[target] ?? Self.defaultRoute(for: target) {
            settings.menuBarPage = route.menuBarPage
            settings.selection = route.destination
        }
        section = target
    }

    static func section(for destination: SettingsDestination,
                        menuBarPage: MenuBarSettingsPage = .icon) -> WorkbenchSection {
        switch destination {
        case .hover, .browser, .windows, .shortcuts: .windows
        case .workspaces: .scenes
        case .effects: .system
        case .general, .permissions: .settings
        case .menuBar:
            switch menuBarPage {
            case .panel, .quickActions: .system
            case .icon, .battery, .network, .audio, .bluetooth, .storage, .performance: .devices
            }
        }
    }

    private func currentRoute(_ settings: SettingsNavigation) -> SettingsRoute {
        SettingsRoute(destination: settings.selection ?? .general, menuBarPage: settings.menuBarPage)
    }

    private static func defaultRoute(for section: WorkbenchSection) -> SettingsRoute? {
        switch section {
        case .windows: SettingsRoute(destination: .hover, menuBarPage: .icon)
        case .devices: SettingsRoute(destination: .menuBar, menuBarPage: .icon)
        case .system: SettingsRoute(destination: .menuBar, menuBarPage: .quickActions)
        case .scenes: SettingsRoute(destination: .workspaces, menuBarPage: .icon)
        case .settings: SettingsRoute(destination: .general, menuBarPage: .icon)
        case .apps, .library, .tools: nil
        }
    }
}
