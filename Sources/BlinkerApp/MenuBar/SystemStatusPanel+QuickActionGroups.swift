import SwiftUI

extension SystemStatusPanel {
    func actionGroup(_ title: LocalizedStringKey,
                     @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading,
                   spacing: preferences.configuration.panelDensity.rowSpacing, content: content)
        }
        .modifier(StatusPanelGroup())
    }

    @ViewBuilder var soundAndPowerActions: some View {
        let config = preferences.configuration
        if config.showsQuickActionMicMute || config.showsQuickActionKeepAwake
            || config.showsQuickActionLowPowerMode
            || (config.showsQuickActionBluetoothConnect && !config.quickActionAudioDeviceAddress.isEmpty) {
            actionGroup("声音与电源") {
                if config.showsQuickActionMicMute {
                    micMuteRow
                }
                if config.showsQuickActionKeepAwake {
                    keepAwakeRow
                }
                if config.showsQuickActionLowPowerMode {
                    lowPowerRow
                }
                if config.showsQuickActionBluetoothConnect, !config.quickActionAudioDeviceAddress.isEmpty {
                    bluetoothConnectRow
                }
            }
        }
    }

    @ViewBuilder var displayActions: some View {
        let config = preferences.configuration
        if config.showsQuickActionDarkMode
            || (config.showsQuickActionResolution && !displayModes.displays.isEmpty)
            || (config.showsQuickActionScreenSaver && SystemScreenActions.isScreenSaverAvailable)
            || config.showsQuickActionDisplaySleep
            || (config.showsQuickActionLockScreen && SystemScreenActions.isLockScreenAvailable) {
            actionGroup("显示与锁屏") {
                if config.showsQuickActionDarkMode {
                    darkModeRow
                }
                if config.showsQuickActionResolution, !displayModes.displays.isEmpty {
                    resolutionRow
                    if displayModes.applyFailed {
                        Text("分辨率切换失败，显示器可能不支持该模式。")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                if config.showsQuickActionScreenSaver, SystemScreenActions.isScreenSaverAvailable {
                    screenActionRow(.screenSaver, title: "屏幕保护", symbol: "photo.on.rectangle",
                                    buttonTitle: "开始", help: String(localized: "立即启动屏幕保护程序"))
                }
                if config.showsQuickActionDisplaySleep {
                    screenActionRow(.displaySleep, title: "关闭显示器", symbol: "moon.zzz",
                                    buttonTitle: "关闭", help: String(localized: "仅关闭所有显示器，Mac 继续运行"))
                }
                if config.showsQuickActionLockScreen, SystemScreenActions.isLockScreenAvailable {
                    actionRow(title: "锁定屏幕", symbol: "lock", buttonTitle: "锁定",
                              help: String(localized: "返回登录窗口，会话与应用保持运行")) {
                        SystemScreenActions.lockScreenNow()
                    }
                }
            }
        }
    }

    private func screenActionRow(_ action: ScreenActionController.Action, title: LocalizedStringKey,
                                 symbol: String, buttonTitle: LocalizedStringKey, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            actionRow(title: title, symbol: symbol,
                      buttonTitle: screenActions.failed == action ? "重试" : buttonTitle, help: help) {
                screenActions.run(action)
            }
            .disabled(screenActions.running != nil)
            if screenActions.running == action {
                OperationProgress(message: String(localized: "正在执行…"))
            } else if screenActions.failed == action {
                Text(action == .screenSaver ? "未能启动屏幕保护，请重试。" : "未能关闭显示器，请重试。")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if screenActions.completed == action {
                Text("已发送请求").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var finderActions: some View {
        let config = preferences.configuration
        if (config.showsQuickActionShowDesktop && desktopActions != nil)
            || config.showsQuickActionDesktopIcons || config.showsQuickActionHiddenFiles
            || config.showsQuickActionShowExtensions || config.showsQuickActionEmptyTrash {
            actionGroup("访达与文件") {
                if config.showsQuickActionShowDesktop, let desktopActions {
                    DesktopQuickActionRow(coordinator: desktopActions)
                }
                if config.showsQuickActionDesktopIcons {
                    finderToggleRow(title: "隐藏桌面图标", symbol: "eye.slash", isOn: desktopIconsBinding)
                }
                if config.showsQuickActionHiddenFiles {
                    finderToggleRow(title: "显示隐藏文件", symbol: "eye", isOn: hiddenFilesBinding)
                }
                if config.showsQuickActionShowExtensions {
                    finderToggleRow(title: "显示扩展名", symbol: "doc.badge.ellipsis", isOn: extensionsBinding)
                }
                if finderToggles.isApplying {
                    Label("正在应用", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                }
                if finderToggles.lastWriteFailed {
                    Text("写入失败，请重试。").font(.caption).foregroundStyle(.red)
                }
                if config.showsQuickActionEmptyTrash {
                    trashRow
                }
            }
        }
    }

    @ViewBuilder var cleaningActions: some View {
        let config = preferences.configuration
        if config.showsQuickActionDisplayCleaning || config.showsQuickActionKeyboardCleaning {
            actionGroup("设备清洁") {
                if config.showsQuickActionDisplayCleaning {
                    cleaningRow(title: "显示器清洁模式", symbol: "display",
                                help: String(localized: "全屏黑屏并锁定键盘；按 Esc 或点击退出")) {
                        cleaning.start(.display)
                    }
                }
                if config.showsQuickActionKeyboardCleaning {
                    cleaningRow(title: "键盘清洁模式", symbol: "keyboard",
                                help: String(localized: "系统级锁定键盘输入；点击退出按钮或连按三次 Esc 结束")) {
                        cleaning.start(.keyboard)
                    }
                }
            }
        }
    }
}
