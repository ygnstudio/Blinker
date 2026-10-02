import BlinkerCore
import SwiftUI

struct WindowBrowserSettingsTab: View {
    @EnvironmentObject var browser: WindowBrowserController

    var body: some View {
        WindowBrowserSettingsContent(
            browser: browser,
            preferences: browser.preferences,
            thumbnails: browser.thumbnails
        )
    }
}

private struct WindowBrowserSettingsContent: View {
    @EnvironmentObject private var permissionAssistant: PermissionAssistantController
    @ObservedObject var browser: WindowBrowserController
    @ObservedObject var preferences: WindowBrowserPreferences
    @ObservedObject var thumbnails: WindowThumbnailStore

    var body: some View {
        Form {
            Section("窗口切换") {
                Toggle("使用 ⌥Tab 切换窗口", isOn: $preferences.switcherEnabled)
                Text("按住 Option 连按 Tab 选择窗口，松开 Option 打开；Shift 反向，Esc 取消。")
                    .font(.caption).foregroundStyle(.secondary)
                if !browser.shortcutAvailable {
                    Text("⌥Tab 已被其他应用占用。请停用冲突的快捷键后重新开启。")
                        .foregroundStyle(.orange)
                }
                Button("打开窗口切换器…") { browser.show() }
            }
            Section("Dock 预览") {
                Toggle("悬停 Dock 图标时显示窗口", isOn: $preferences.dockEnabled)
                SliderReadoutRow(label: String(localized: "出现延迟"),
                                 readout: "\(Int(preferences.dockAppearanceMilliseconds)) ms",
                                 value: $preferences.dockAppearanceMilliseconds, range: 0 ... 1000, step: 50)
                    .disabled(!preferences.dockEnabled)
                SliderReadoutRow(label: String(localized: "移出后关闭延迟"),
                                 readout: "\(Int(preferences.dockDismissalMilliseconds)) ms",
                                 value: $preferences.dockDismissalMilliseconds, range: 100 ... 1000, step: 50)
                    .disabled(!preferences.dockEnabled)
                Text("移入预览可切换或管理窗口；移出后稍作停留再关闭，方便从 Dock 移入预览。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("预览大小") {
                SliderReadoutRow(label: String(localized: "大小"),
                                 readout: "\(Int((preferences.previewScale * 100).rounded()))%",
                                 value: $preferences.previewScale, range: 0.5 ... 1.5, step: 0.05)
                Text("同时调整 Dock 预览和窗口切换器；也可在预览底部的大小菜单中调整。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("窗口缩略图") {
                Toggle("显示窗口缩略图", isOn: $preferences.thumbnailsEnabled)
                if preferences.thumbnailsEnabled, !thumbnails.permissionGranted {
                    Text("窗口缩略图需要屏幕录制权限。未授权时仍可使用图标和标题切换窗口。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("授权窗口缩略图…") { permissionAssistant.show(for: .screenRecording) }
                    Button("重新检查权限") { thumbnails.checkPermission() }
                }
                Text("仅在预览打开时采集，图片只缓存在内存中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("显示范围") {
                Toggle("显示标签页", isOn: $preferences.includeTabs)
                Text("将标准 macOS 窗口标签页和 Safari 标签页分别列出；无缓存画面的后台标签页显示图标和标题。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("包括最小化和隐藏的窗口", isOn: $preferences.includeMinimized)
                Toggle("仅显示当前显示器的窗口", isOn: $preferences.currentDisplayOnly)
            }
        }
        .formStyle(.grouped)
        .onAppear { thumbnails.checkPermission() }
    }
}
