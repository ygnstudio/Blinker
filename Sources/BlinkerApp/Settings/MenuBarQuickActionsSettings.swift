import SwiftUI

/// Status-icon settings page for the panel quick actions block: row
/// visibility, the Bluetooth connect target, plus the Shortcut slot names.
/// Slot editing is draft-based so normalization never reshuffles the list
/// mid-typing.
struct MenuBarQuickActionsSettings: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var monitor: SystemStatusMonitor
    @State private var slotDrafts: [String] = ["", "", ""]

    var body: some View {
        Section {
            Toggle("显示「麦克风静音」", isOn: binding(\.showsQuickActionMicMute))
            Toggle("显示「保持唤醒」", isOn: binding(\.showsQuickActionKeepAwake))
            Toggle("显示「低电量模式」", isOn: binding(\.showsQuickActionLowPowerMode))
            Toggle("显示「连接蓝牙耳机」", isOn: binding(\.showsQuickActionBluetoothConnect))
        } header: {
            Text("声音与电源")
        } footer: {
            Text("这里只选择面板中显示的操作，不会改变系统状态。")
        }
        Section {
            Toggle("显示「深色模式」", isOn: binding(\.showsQuickActionDarkMode))
            Toggle("显示「显示模式」", isOn: binding(\.showsQuickActionResolution))
            Toggle("显示「屏幕保护」", isOn: binding(\.showsQuickActionScreenSaver))
            Toggle("显示「关闭显示器」", isOn: binding(\.showsQuickActionDisplaySleep))
            Toggle("显示「锁定屏幕」", isOn: binding(\.showsQuickActionLockScreen))
        } header: {
            Text("显示与锁屏")
        } footer: {
            Text("前往快速操作面板执行这些操作。")
        }
        Section {
            Toggle("显示「显示桌面 / 恢复窗口」", isOn: binding(\.showsQuickActionShowDesktop))
            Toggle("显示「隐藏桌面图标」", isOn: binding(\.showsQuickActionDesktopIcons))
            Toggle("显示「显示隐藏文件」", isOn: binding(\.showsQuickActionHiddenFiles))
            Toggle("显示「显示扩展名」", isOn: binding(\.showsQuickActionShowExtensions))
            Toggle("显示「清空回收站」", isOn: binding(\.showsQuickActionEmptyTrash))
        } header: {
            Text("访达与文件")
        } footer: {
            Text("这些开关只控制入口是否显示。清空回收站仍需在面板中确认。")
        }
        Section {
            Toggle("显示「显示器清洁模式」", isOn: binding(\.showsQuickActionDisplayCleaning))
            Toggle("显示「键盘清洁模式」", isOn: binding(\.showsQuickActionKeyboardCleaning))
        } header: {
            Text("设备清洁")
        } footer: {
            Text("开启后显示清洁入口，使用时会检查所需权限。")
        }
        bluetoothDeviceSection
        Section {
            ForEach(0 ..< 3, id: \.self) { index in
                LabeledContent {
                    TextField("快捷指令 \(index + 1)", text: slotBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        .onSubmit(commitSlots)
                } label: {
                    Text("快捷指令 \(index + 1)")
                }
            }
        } header: {
            Text("快捷指令")
        } footer: {
            Text("名称需与「快捷指令」App 中的一致。输入自动保存，留空不显示。")
        }
        .onAppear(perform: seedDrafts)
    }

    /// The connect row's target: paired audio devices from the latest
    /// snapshot, ghosts excluded. A device missing from the snapshot keeps
    /// its saved name in the picker so the choice never looks lost.
    @ViewBuilder
    private var bluetoothDeviceSection: some View {
        let devices = (monitor.snapshot.bluetoothDevices ?? [])
            .filter { $0.kind == .audio && !$0.isUnpairedGhost }
        Section {
            EclipsePicker("目标设备", selection: deviceAddressBinding) {
                Text("未选择").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
                let savedAddress = preferences.configuration.quickActionAudioDeviceAddress
                if !savedAddress.isEmpty,
                   !devices.contains(where: { $0.id == savedAddress }) {
                    Text(preferences.configuration.quickActionAudioDeviceName)
                        .tag(savedAddress)
                }
            }
        } header: {
            Text("蓝牙耳机")
        } footer: {
            Text("选择已配对的音频设备后，面板出现「连接」行；连接与编解码器、断开共用同一蓝牙授权，未授权时面板会给出指引。")
        }
    }

    /// Picking a device caches its name alongside the address, so the panel
    /// row still reads well when the device is off or out of range. Re-
    /// picking the entry the snapshot no longer lists keeps its saved name.
    private var deviceAddressBinding: Binding<String> {
        Binding(
            get: { preferences.configuration.quickActionAudioDeviceAddress },
            set: { address in
                let devices = monitor.snapshot.bluetoothDevices ?? []
                let current = preferences.configuration
                let name = devices.first { $0.id == address }?.name
                    ?? (address == current.quickActionAudioDeviceAddress
                        ? current.quickActionAudioDeviceName : "")
                preferences.update {
                    $0.quickActionAudioDeviceAddress = address
                    $0.quickActionAudioDeviceName = name
                }
            }
        )
    }

    private func seedDrafts() {
        let slots = preferences.configuration.shortcutSlots
        slotDrafts = (0 ..< 3).map { index in index < slots.count ? slots[index] : "" }
    }

    private func slotBinding(_ index: Int) -> Binding<String> {
        Binding(get: { slotDrafts[index] },
                set: {
                    slotDrafts[index] = $0
                    commitSlots()
                })
    }

    private func commitSlots() {
        preferences.update { $0.shortcutSlots = slotDrafts }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
