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
            Toggle("麦克风静音", isOn: binding(\.showsQuickActionMicMute))
            Toggle("显示器清洁模式", isOn: binding(\.showsQuickActionDisplayCleaning))
            Toggle("键盘清洁模式", isOn: binding(\.showsQuickActionKeyboardCleaning))
            Toggle("清空回收站", isOn: binding(\.showsQuickActionEmptyTrash))
            Toggle("保持唤醒", isOn: binding(\.showsQuickActionKeepAwake))
            Toggle("隐藏桌面图标", isOn: binding(\.showsQuickActionDesktopIcons))
            Toggle("显示隐藏文件", isOn: binding(\.showsQuickActionHiddenFiles))
            Toggle("屏幕保护", isOn: binding(\.showsQuickActionScreenSaver))
            Toggle("关闭显示器", isOn: binding(\.showsQuickActionDisplaySleep))
            Toggle("锁定屏幕", isOn: binding(\.showsQuickActionLockScreen))
            Toggle("连接蓝牙耳机", isOn: binding(\.showsQuickActionBluetoothConnect))
        } header: {
            Text("面板显示")
        } footer: {
            Text("显示器清洁以全屏黑窗覆盖所有屏幕，无需权限。键盘清洁通过系统级事件拦截锁定键盘与媒体键，需辅助功能与输入监控权限；权限不足时会先引导授权。")
            Text("清空回收站经访达进行，删除前需二次确认；首次使用需允许 Blinker 控制访达。")
            Text("保持唤醒仅阻止系统自动睡眠，不影响合盖与电源策略。访达两项开关写入后重启访达生效，桌面会短暂重绘；系统缺少锁屏入口时该行自动隐藏。")
        }
        bluetoothDeviceSection
        Section {
            ForEach(0 ..< 3, id: \.self) { index in
                TextField("快捷指令 \(index + 1)", text: slotBinding(index))
                    .onSubmit(commitSlots)
            }
        } header: {
            Text("快捷指令")
        } footer: {
            Text("名称需与「快捷指令」App 中的一致；留空的槽位不出现在面板。回车保存。")
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
            Picker("目标设备", selection: deviceAddressBinding) {
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
                set: { slotDrafts[index] = $0 })
    }

    private func commitSlots() {
        preferences.update { $0.shortcutSlots = slotDrafts }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
