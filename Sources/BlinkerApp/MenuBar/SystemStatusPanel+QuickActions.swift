import SwiftUI

/// The quick actions block: microphone mute for the default input, display
/// and keyboard cleaning overlays, trash emptying, and the user's named
/// Shortcut slots. Rows the user hides in settings simply leave the block
/// out; an entirely empty block hides the section.
extension SystemStatusPanel {
    enum ShortcutSlotState: Equatable {
        case idle, running, failed(ShortcutRunner.Failure)
    }

    /// True when at least one quick action row is configured to show.
    var quickActionsHasRows: Bool {
        let configuration = preferences.configuration
        return configuration.showsQuickActionMicMute
            || configuration.showsQuickActionDisplayCleaning
            || configuration.showsQuickActionKeyboardCleaning
            || configuration.showsQuickActionEmptyTrash
            || configuration.showsQuickActionKeepAwake
            || configuration.showsQuickActionDesktopIcons
            || configuration.showsQuickActionHiddenFiles
            || (configuration.showsQuickActionScreenSaver && SystemScreenActions.isScreenSaverAvailable)
            || configuration.showsQuickActionDisplaySleep
            || (configuration.showsQuickActionLockScreen && SystemScreenActions.isLockScreenAvailable)
            || (configuration.showsQuickActionBluetoothConnect
                && !configuration.quickActionAudioDeviceAddress.isEmpty)
            || !configuration.shortcutSlots.isEmpty
    }

    /// The panel's second page. An entirely unconfigured page still keeps its
    /// heading gear so the way back to settings stays discoverable. Landing
    /// on the page re-syncs the Finder switches with the preference domain.
    var quickActionsPage: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.sectionSpacing) {
            if quickActionsHasRows {
                quickActionsSection
            } else {
                heading("快速操作", symbol: "bolt.circle", page: .quickActions)
                Text("没有已开启的操作，可在快速操作设置中开启。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { finderToggles.refresh() }
    }

    @ViewBuilder
    var quickActionsSection: some View {
        let configuration = preferences.configuration
        if quickActionsHasRows {
            VStack(alignment: .leading,
                   spacing: configuration.panelDensity.rowSpacing) {
                heading("快速操作", symbol: "bolt.circle", page: .quickActions)
                if configuration.showsQuickActionMicMute {
                    micMuteRow
                }
                if configuration.showsQuickActionDisplayCleaning {
                    cleaningRow(title: LocalizedStringKey("显示器清洁模式"), symbol: "display",
                                help: String(localized: "全屏黑屏并锁定键盘；按 Esc 或点击退出")) {
                        cleaning.start(.display)
                    }
                }
                if configuration.showsQuickActionKeyboardCleaning {
                    cleaningRow(title: LocalizedStringKey("键盘清洁模式"), symbol: "keyboard",
                                help: String(localized: "系统级锁定键盘输入；点击退出按钮或连按三次 Esc 结束")) {
                        cleaning.start(.keyboard)
                    }
                }
                if configuration.showsQuickActionEmptyTrash {
                    trashRow
                }
                if configuration.showsQuickActionKeepAwake {
                    keepAwakeRow
                }
                if configuration.showsQuickActionDesktopIcons {
                    finderToggleRow(title: "隐藏桌面图标", symbol: "eye.slash",
                                    isOn: desktopIconsBinding)
                }
                if configuration.showsQuickActionHiddenFiles {
                    finderToggleRow(title: "显示隐藏文件", symbol: "eye",
                                    isOn: hiddenFilesBinding)
                }
                if finderToggles.lastWriteFailed,
                   configuration.showsQuickActionDesktopIcons
                    || configuration.showsQuickActionHiddenFiles {
                    Text("写入失败，请重试。")
                        .font(.caption).foregroundStyle(.red)
                }
                if configuration.showsQuickActionScreenSaver,
                   SystemScreenActions.isScreenSaverAvailable {
                    actionRow(title: "屏幕保护", symbol: "photo.on.rectangle",
                              buttonTitle: "开始",
                              help: String(localized: "立即启动屏幕保护程序")) {
                        try? SystemScreenActions.startScreenSaver()
                    }
                }
                if configuration.showsQuickActionDisplaySleep {
                    actionRow(title: "关闭显示器", symbol: "moon.zzz",
                              buttonTitle: "关闭",
                              help: String(localized: "仅关闭所有显示器，Mac 继续运行")) {
                        try? SystemScreenActions.sleepDisplays()
                    }
                }
                if configuration.showsQuickActionLockScreen,
                   SystemScreenActions.isLockScreenAvailable {
                    actionRow(title: "锁定屏幕", symbol: "lock",
                              buttonTitle: "锁定",
                              help: String(localized: "返回登录窗口，会话与应用保持运行")) {
                        SystemScreenActions.lockScreenNow()
                    }
                }
                if configuration.showsQuickActionBluetoothConnect,
                   !configuration.quickActionAudioDeviceAddress.isEmpty {
                    bluetoothConnectRow
                }
                ForEach(configuration.shortcutSlots, id: \.self, content: shortcutRow)
            }
        }
    }

    private var micMuteRow: some View {
        HStack(spacing: 6) {
            Image(systemName: audio.input?.isMuted == true ? "mic.slash.fill" : "mic.fill")
                .frame(width: 18)
                .foregroundStyle(audio.input?.isMuted == true ? Color.orange : Color.primary)
            Text("麦克风")
            if audio.input?.isMuted == true {
                Text("已静音")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Toggle("麦克风静音", isOn: micMuteBinding)
                .toggleStyle(.switch).labelsHidden()
                .disabled(audio.input?.canMute != true)
        }
        .font(.callout)
    }

    private var micMuteBinding: Binding<Bool> {
        Binding(get: { audio.input?.isMuted == true },
                set: { audio.setInputMuted($0) })
    }

    private var keepAwakeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.saucer").frame(width: 18)
                .foregroundStyle(keepAwake.isActive ? Color.orange : Color.primary)
            Text("保持唤醒")
            Spacer(minLength: 8)
            Toggle("保持唤醒", isOn: keepAwakeBinding)
                .toggleStyle(.switch).labelsHidden()
        }
        .font(.callout)
    }

    private var keepAwakeBinding: Binding<Bool> {
        Binding(get: { keepAwake.isActive },
                set: { keepAwake.setActive($0) })
    }

    /// The two Finder switches share one shape. The desktop-icons row reads
    /// inverted — ON means "icons are hidden", matching the mic-mute row
    /// where ON names the active state.
    private func finderToggleRow(title: LocalizedStringKey, symbol: String,
                                 isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch).labelsHidden()
        }
        .font(.callout)
    }

    private var desktopIconsBinding: Binding<Bool> {
        Binding(get: { !finderToggles.desktopIconsShown },
                set: { finderToggles.setDesktopIconsShown(!$0) })
    }

    private var hiddenFilesBinding: Binding<Bool> {
        Binding(get: { finderToggles.hiddenFilesShown },
                set: { finderToggles.setHiddenFilesShown($0) })
    }

    private func cleaningRow(title: LocalizedStringKey, symbol: String, help: String,
                             action: @escaping () -> Void) -> some View {
        actionRow(title: title, symbol: symbol, buttonTitle: "开始", help: help, action: action)
    }

    /// One-shot actions share the cleaning rows' shape: icon, title, a
    /// trailing text button. The button carries the verb since these rows
    /// hold no persistent state.
    private func actionRow(title: LocalizedStringKey, symbol: String,
                           buttonTitle: LocalizedStringKey, help: String,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderless)
                .help(help)
        }
        .font(.callout)
    }

    /// Bluetooth audio reconnect. The row appears once a device is picked
    /// in settings; the connect call shares the Bluetooth device-control
    /// grant with codec reading and disconnect, so without the grant the
    /// row explains instead of acting.
    private var bluetoothConnectRow: some View {
        let configuration = preferences.configuration
        let address = configuration.quickActionAudioDeviceAddress
        let live = monitor.snapshot.bluetoothDevices?.first { $0.id == address }
        let name = live?.name ?? (configuration.quickActionAudioDeviceName.isEmpty
            ? address : configuration.quickActionAudioDeviceName)
        let canControl = configuration.enablesBluetoothDeviceControl
            && scanner.authorization == .allowedAlways
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: live?.kind.symbolName ?? "headphones").frame(width: 18)
                Text(name).lineLimit(1)
                Spacer(minLength: 8)
                if live?.isConnected == true {
                    Text("已连接")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    Button("连接") { connectBluetoothDevice(address) }
                        .buttonStyle(.borderless)
                        .disabled(!canControl)
                        .help(String(localized: "重新连接该设备，配对关系保持不变"))
                }
            }
            .font(.callout)
            if !canControl {
                Text("需要在蓝牙设置中开启「编解码器与断开操作」并完成蓝牙授权。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Same cadence as disconnect: the profiler cache holds the previous
    /// list for a few seconds, so refresh quickly and again after it
    /// expires.
    private func connectBluetoothDevice(_ address: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = BluetoothConnectionDetails.connect(address: address)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                monitor.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                monitor.refresh()
            }
        }
    }

    /// Trash row: the snapshot's item count (hidden without Full Disk
    /// Access), a confirm-before-empty button, and an inline note when the
    /// Finder refuses. Emptying is destructive, so the button never acts
    /// directly; it runs through the Finder, which asks for Automation
    /// consent once and needs no other grant.
    private var trashRow: some View {
        let count = monitor.snapshot.trashItemCount
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "trash").frame(width: 18)
                Text("回收站")
                if let count, count > 0 {
                    Text(String(localized: "\(count) 项"))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                if trashEmptier.isEmptying {
                    ProgressView().controlSize(.small)
                } else {
                    Button("清空") { confirmingTrashEmpty = true }
                        .buttonStyle(.borderless)
                        .disabled(count == 0)
                        .help(String(localized: "清空回收站"))
                }
            }
            .font(.callout)
            switch trashEmptier.failure {
            case .automationDenied:
                Text("需要允许 Blinker 控制访达。")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                settingsLink("打开自动化设置…",
                             destination: "com.apple.preference.security?Privacy_Automation")
                    .font(.caption)
            case .failed(let message):
                Text(message)
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }
        }
        .confirmationDialog("清空回收站？", isPresented: $confirmingTrashEmpty,
                            titleVisibility: .visible) {
            Button("清空回收站", role: .destructive) {
                trashEmptier.empty { monitor.refresh() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除回收站中的所有项目，此操作无法撤销。")
        }
    }

    private func shortcutRow(_ name: String) -> some View {
        let state = shortcutSlotStates[name] ?? .idle
        return HStack(spacing: 6) {
            Image(systemName: "command").frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if case .failed(let failure) = state {
                    Text(failureMessage(failure))
                        .font(.caption).foregroundStyle(.red)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if state == .running {
                ProgressView().controlSize(.small)
            } else {
                Button("运行") { runShortcut(name) }
                    .buttonStyle(.borderless)
            }
        }
        .font(.callout)
    }

    private func runShortcut(_ name: String) {
        guard shortcutSlotStates[name] != .running else { return }
        shortcutSlotStates[name] = .running
        shortcutRunner.run(name) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    shortcutSlotStates[name] = .idle
                case .failure(let failure):
                    shortcutSlotStates[name] = .failed(failure)
                }
            }
        }
    }

    private func failureMessage(_ failure: ShortcutRunner.Failure) -> String {
        switch failure {
        case .notFound:
            String(localized: "未找到同名快捷指令")
        case .timedOut:
            String(localized: "运行超时")
        case .failed(let message):
            String(localized: "运行失败：\(message)")
        }
    }
}
