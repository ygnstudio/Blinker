import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SettingsPlaceholderScene()
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("关于 Blinker", action: appDelegate.openAbout)
                }
                // Every window, including onboarding, must open the same native settings window.
                CommandGroup(replacing: .appSettings) {
                    Button("设置…", action: appDelegate.openSettings)
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .help) {
                    if let url = ProjectLinks.guide {
                        Link("Blinker 使用指南", destination: url)
                    }
                    Button("重新查看引导", action: appDelegate.replayOnboarding)
                    Divider()
                    Button("检查应用兼容性…") { CompatibilityWindowController.shared.show() }
                    Button("打开真实测试窗口…") { CompatibilityWindowController.shared.showTestWindow() }
                    Divider()
                    if let url = ProjectLinks.feedback {
                        Link("反馈问题", destination: url)
                    }
                }
            }
    }
}

/// Placeholder scene that only satisfies SwiftUI's `Scene` requirement.
///
/// The real settings window is a plain `NSWindow` created and owned by the
/// app delegate (see `openSettings()`); this scene renders nothing.
///
/// Do NOT swap this for a suppressed `Window` scene: on macOS 26 a `Window`
/// with `.defaultLaunchBehavior(.suppressed)` stalls the SwiftUI launch so
/// `applicationDidFinishLaunching` never fires — no menu bar item, no
/// interceptor, nothing (verified 2026-09-16: zero subsystem log entries
/// after launch).
private struct SettingsPlaceholderScene: Scene {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
