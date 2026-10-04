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
    @EnvironmentObject private var permissions: PermissionController
    @EnvironmentObject private var permissionAssistant: PermissionAssistantController
    @ObservedObject var browser: WindowBrowserController
    @ObservedObject var preferences: WindowBrowserPreferences
    @ObservedObject var thumbnails: WindowThumbnailStore

    var body: some View {
        Form {
            if !permissions.accessibilityGranted {
                Section {
                    Text("窗口预览与切换需要辅助功能权限。")
                        .foregroundStyle(.secondary)
                    Button("授权辅助功能…") { permissionAssistant.show(for: .accessibility) }
                }
            }
            keyboardSection
            dockSection
            contentSection
            appearanceSection
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("使用 ⌥Tab 切换窗口", isOn: $preferences.switcherEnabled)
            if preferences.switcherEnabled, !browser.shortcutAvailable {
                Text("⌥Tab 已被其他应用占用。请停用冲突的快捷键后重新开启。")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("键盘窗口切换")
        } footer: {
            Text("按住 Option 连按 Tab 选择窗口，松开 Option 打开；Shift 反向，Esc 取消。")
        }
    }

    private var dockSection: some View {
        Section {
            Toggle("悬停 Dock 图标时显示窗口", isOn: $preferences.dockEnabled)
            Group {
                SliderReadoutRow(label: String(localized: "出现延迟"),
                                 readout: "\(Int(preferences.dockAppearanceMilliseconds)) ms",
                                 value: $preferences.dockAppearanceMilliseconds, range: 0 ... 1000, step: 50)
                SliderReadoutRow(label: String(localized: "移出后关闭延迟"),
                                 readout: "\(Int(preferences.dockDismissalMilliseconds)) ms",
                                 value: $preferences.dockDismissalMilliseconds, range: 100 ... 1000, step: 50)
            }
            .padding(.leading, 16)
            .disabled(!preferences.dockEnabled)
        } header: {
            Text("Dock 悬停预览")
        } footer: {
            Text("移入预览可切换或管理窗口；移出后稍作停留再关闭，方便从 Dock 移入预览。")
        }
    }

    private var contentSection: some View {
        Section {
            Toggle("显示标签页", isOn: $preferences.includeTabs)
            Toggle("包括最小化和隐藏的窗口", isOn: $preferences.includeMinimized)
            Toggle("仅显示当前显示器的窗口", isOn: $preferences.currentDisplayOnly)
        } header: {
            Text("共用的显示内容")
        } footer: {
            Text("标签页支持标准 macOS 标签栏和 Safari；没有缓存画面的后台标签页显示图标和标题。")
        }
    }

    private var appearanceSection: some View {
        Section {
            SliderReadoutRow(label: String(localized: "预览大小"),
                             readout: "\(Int((preferences.previewScale * 100).rounded()))%",
                             value: $preferences.previewScale, range: 0.5 ... 1.5, step: 0.05)
            Toggle("显示窗口缩略图", isOn: $preferences.thumbnailsEnabled)
            if preferences.thumbnailsEnabled, !thumbnails.permissionGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未授权屏幕录制，当前显示图标和标题。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("授权窗口缩略图…") { permissionAssistant.show(for: .screenRecording) }
                }
                .padding(.leading, 16)
            }
            Button("打开窗口面板…") { browser.show() }
        } header: {
            Text("共用的预览外观")
        } footer: {
            Text("显示内容和预览外观供键盘切换、Dock 悬停预览与手动窗口面板共用。缩略图只在面板打开时采集并缓存在内存中。")
        }
    }
}
