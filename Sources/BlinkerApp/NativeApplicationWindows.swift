import AppKit
import SwiftUI

/// One native SwiftUI scene, shared by rules, settings and every contextual deep link.
@MainActor
final class NativeApplicationWindows {
    private let scenes: NSHostingSceneRepresentation<NativeApplicationScenes>
    private let navigation: WorkbenchNavigation
    private let settingsNavigation: SettingsNavigation

    init(settings: AnyView, rules: AnyView, navigation: WorkbenchNavigation,
         settingsNavigation: SettingsNavigation, onShowStatusPanel: @escaping () -> Void) {
        self.navigation = navigation
        self.settingsNavigation = settingsNavigation
        let content = AnyView(WorkbenchRootView(
            rules: rules, settings: settings, navigation: navigation,
            settingsNavigation: settingsNavigation, onShowStatusPanel: onShowStatusPanel
        ))
        scenes = NSHostingSceneRepresentation {
            NativeApplicationScenes(content: content)
        }
    }

    func install() {
        NSApp.addSceneRepresentation(scenes)
    }

    func showSettings() {
        navigation.showSettings(using: settingsNavigation)
        showCurrent()
    }

    func showRules() {
        navigation.showApplications()
        showCurrent()
    }

    func showCurrent() {
        NSApp.activate()
        // A stable value reuses this workspace after closing or minimizing it.
        scenes.environment.openWindow(id: "workbench", value: "main")
    }
}

private struct NativeApplicationScenes: Scene {
    let content: AnyView

    var body: some Scene {
        WindowGroup("Blinker", id: "workbench", for: String.self) { _ in
            content.frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultLaunchBehavior(.suppressed)
    }
}
