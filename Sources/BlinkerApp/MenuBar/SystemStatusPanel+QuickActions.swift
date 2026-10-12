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
            || (configuration.showsQuickActionShowDesktop && desktopActions != nil)
            || configuration.showsQuickActionDesktopIcons
            || configuration.showsQuickActionHiddenFiles
            || configuration.showsQuickActionShowExtensions
            || configuration.showsQuickActionLowPowerMode
            || (configuration.showsQuickActionScreenSaver && SystemScreenActions.isScreenSaverAvailable)
            || configuration.showsQuickActionDisplaySleep
            || (configuration.showsQuickActionLockScreen && SystemScreenActions.isLockScreenAvailable)
            || configuration.showsQuickActionDarkMode
            || (configuration.showsQuickActionResolution && !displayModes.displays.isEmpty)
            || (configuration.showsQuickActionBluetoothConnect
                && !configuration.quickActionAudioDeviceAddress.isEmpty)
            || !configuration.shortcutSlots.isEmpty
    }

    /// The panel's second page. An entirely unconfigured page still keeps its
    /// management menu so the way back to settings stays discoverable. Landing
    /// on the page re-syncs the Finder switches, the dark-mode switch and the
    /// display list with the system.
    var quickActionsPage: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.sectionSpacing) {
            if quickActionsHasRows {
                quickActionsSection
            } else {
                Text("没有已开启的操作，可在快速操作设置中开启。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            finderToggles.refresh()
            appearanceToggle.refresh()
            displayModes.refresh()
            lowPower.refresh()
        }
    }

    var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: preferences.configuration.panelDensity.sectionSpacing) {
            soundAndPowerActions
            displayActions
            finderActions
            cleaningActions
            if !preferences.configuration.shortcutSlots.isEmpty {
                actionGroup("快捷指令") {
                    ForEach(preferences.configuration.shortcutSlots, id: \.self, content: shortcutRow)
                }
            }
        }
    }

    var micMuteRow: some View {
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
        .font(.body).frame(minHeight: 28)
    }

    var micMuteBinding: Binding<Bool> {
        Binding(get: { audio.input?.isMuted == true },
                set: { audio.setInputMuted($0) })
    }

    var keepAwakeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.saucer").frame(width: 18)
                .foregroundStyle(keepAwake.isActive ? Color.orange : Color.primary)
            Text("保持唤醒")
            Spacer(minLength: 8)
            Toggle("保持唤醒", isOn: keepAwakeBinding)
                .toggleStyle(.switch).labelsHidden()
        }
        .font(.body).frame(minHeight: 28)
    }

    var keepAwakeBinding: Binding<Bool> {
        Binding(get: { keepAwake.isActive },
                set: { keepAwake.setActive($0) })
    }

    /// The two Finder switches share one shape. The desktop-icons row reads
    /// inverted — ON means "icons are hidden", matching the mic-mute row
    /// where ON names the active state.
    func finderToggleRow(title: LocalizedStringKey, symbol: String,
                         isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch).labelsHidden()
                .disabled(finderToggles.isApplying)
        }
        .font(.body).frame(minHeight: 28)
    }

    var desktopIconsBinding: Binding<Bool> {
        Binding(get: { !finderToggles.desktopIconsShown },
                set: { finderToggles.setDesktopIconsShown(!$0) })
    }

    var hiddenFilesBinding: Binding<Bool> {
        Binding(get: { finderToggles.hiddenFilesShown },
                set: { finderToggles.setHiddenFilesShown($0) })
    }

    var extensionsBinding: Binding<Bool> {
        Binding(get: { finderToggles.extensionsShown },
                set: { finderToggles.setExtensionsShown($0) })
    }

    /// Low power mode: a toggle whose write path crosses into the
    /// privileged helper. The issue surfaces inline, mirroring the dark
    /// mode row's automation-denied guidance.
    var lowPowerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: lowPower.isOn ? "battery.25" : "battery.100")
                    .frame(width: 18)
                Text("低电量模式")
                Spacer(minLength: 8)
                if lowPower.isApplying {
                    ProgressView().controlSize(.mini).accessibilityLabel("正在应用")
                }
                Toggle("低电量模式", isOn: lowPowerBinding)
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(lowPower.isApplying)
            }
            .font(.body).frame(minHeight: 28)
            switch lowPower.issue {
            case .approvalRequired:
                Text("需在「系统设置 → 通用 → 登录项与扩展」中允许 Blinker 的后台项目。")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .helperUnavailable:
                Text("后台组件未安装；打包后的 Blinker 才提供此开关。")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .writeFailed:
                Text("写入失败，请重试。")
                    .font(.caption).foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
    }

    var lowPowerBinding: Binding<Bool> {
        Binding(get: { lowPower.isOn },
                set: { lowPower.setLowPowerMode($0) })
    }

    /// Dark mode sits with the other system-wide visual switches. Writing
    /// runs through System Events, so a missing Automation consent explains
    /// itself inline the same way the trash row does.
    var darkModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: appearanceToggle.isDarkMode ? "moon.fill" : "moon")
                    .frame(width: 18)
                Text("深色模式")
                Spacer(minLength: 8)
                if appearanceToggle.isApplying {
                    ProgressView().controlSize(.mini).accessibilityLabel("正在应用")
                }
                Toggle("深色模式", isOn: darkModeBinding)
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(appearanceToggle.isApplying)
            }
            .font(.body).frame(minHeight: 28)
            switch appearanceToggle.failure {
            case .automationDenied:
                Text("需要允许 Blinker 控制系统事件。")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                settingsLink("打开自动化设置…",
                             destination: "com.apple.preference.security?Privacy_Automation")
                    .font(.caption)
            case let .failed(message):
                Text(message)
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }
        }
    }

    var darkModeBinding: Binding<Bool> {
        Binding(get: { appearanceToggle.isDarkMode },
                set: { appearanceToggle.setDarkMode($0) })
    }

    /// Keep display details inside the menu so this action shares the other rows' geometry.
    var resolutionRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "display").frame(width: 18)
            Text("显示模式")
            Spacer(minLength: 8)
            Menu {
                ForEach(displayModes.displays) { display in
                    if displayModes.displays.count == 1 {
                        Section(display.name) { displayModeOptions(display) }
                    } else {
                        Menu(display.name) { displayModeOptions(display) }
                    }
                }
            } label: {
                if displayModes.displays.count == 1,
                   let mode = displayModes.displays.first?.modes.first(where: \.isCurrent) {
                    Text(verbatim: "\(mode.width) × \(mode.height)")
                        .monospacedDigit()
                } else {
                    Text("选择显示器")
                }
            }
            .menuStyle(.borderedButton)
            .fixedSize()
            .accessibilityLabel("显示模式")
            .accessibilityValue(displayModes.displays.count == 1
                ? displayModes.displays.first?.modes.first(where: \.isCurrent)?.title ?? ""
                : "")
        }
        .font(.body).frame(minHeight: 28)
    }

    private func displayModeOptions(_ display: DisplayEntry) -> some View {
        ForEach(display.modes) { mode in
            Button {
                displayModes.setMode(mode, for: display)
            } label: {
                if mode.isCurrent {
                    Label(mode.title, systemImage: "checkmark")
                } else {
                    Text(mode.title)
                }
            }
        }
    }

    func cleaningRow(title: LocalizedStringKey, symbol: String, help: String,
                     action: @escaping () -> Void) -> some View {
        actionRow(title: title, symbol: symbol, buttonTitle: "开始", help: help, action: action)
    }

    /// One-shot actions share the cleaning rows' shape: icon, title, a
    /// trailing text button. The button carries the verb since these rows
    /// hold no persistent state.
    func actionRow(title: LocalizedStringKey, symbol: String,
                   buttonTitle: LocalizedStringKey, help: String,
                   action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .help(help)
        }
        .font(.body).frame(minHeight: 28)
    }

    /// Bluetooth audio reconnect. The row appears once a device is picked
    /// in settings; the connect call shares the Bluetooth device-control
    /// grant with codec reading and disconnect, so without the grant the
    /// row explains instead of acting.
    var bluetoothConnectRow: some View {
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
                        .buttonStyle(.bordered)
                        .disabled(!canControl)
                        .help(String(localized: "重新连接该设备，配对关系保持不变"))
                }
            }
            .font(.body).frame(minHeight: 28)
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
    func connectBluetoothDevice(_ address: String) {
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
    var trashRow: some View {
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
                        .buttonStyle(.bordered)
                        .disabled(count == 0)
                        .help(String(localized: "清空回收站"))
                }
            }
            .font(.body).frame(minHeight: 28)
            switch trashEmptier.failure {
            case .automationDenied:
                Text("需要允许 Blinker 控制访达。")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                settingsLink("打开自动化设置…",
                             destination: "com.apple.preference.security?Privacy_Automation")
                    .font(.caption)
            case let .failed(message):
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

    func shortcutRow(_ name: String) -> some View {
        let state = shortcutSlotStates[name] ?? .idle
        return HStack(spacing: 6) {
            Image(systemName: "command").frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if case let .failed(failure) = state {
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
                    .buttonStyle(.bordered)
            }
        }
        .font(.body).frame(minHeight: 28)
    }

    func runShortcut(_ name: String) {
        guard shortcutSlotStates[name] != .running else { return }
        shortcutSlotStates[name] = .running
        shortcutRunner.run(name) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    shortcutSlotStates[name] = .idle
                case let .failure(failure):
                    shortcutSlotStates[name] = .failed(failure)
                }
            }
        }
    }

    func failureMessage(_ failure: ShortcutRunner.Failure) -> String {
        switch failure {
        case .notFound:
            String(localized: "未找到同名快捷指令")
        case .timedOut:
            String(localized: "运行超时")
        case let .failed(message):
            String(localized: "运行失败：\(message)")
        }
    }
}
