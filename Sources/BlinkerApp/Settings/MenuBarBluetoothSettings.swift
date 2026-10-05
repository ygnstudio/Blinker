import AppKit
import SwiftUI

/// Status-icon settings page for the panel bluetooth block: paired-device
/// list management plus the nearby-scan toggle with its permission guidance.
struct MenuBarBluetoothSettings: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var monitor: SystemStatusMonitor
    @ObservedObject var scanner: BluetoothLEScanner

    var body: some View {
        deviceSection
        displaySection
        nearbySection
    }

    private var orderedDevices: [BluetoothDevice] {
        BluetoothDeviceOrdering.ordered(monitor.snapshot.bluetoothDevices ?? [],
                                        order: preferences.configuration.bluetoothDeviceOrder)
    }

    @ViewBuilder
    private var deviceSection: some View {
        let devices = orderedDevices
        Section {
            if devices.isEmpty {
                Text(monitor.snapshot.bluetoothDevices == nil
                    ? String(localized: "正在读取…") : String(localized: "没有已配对的蓝牙设备。"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    HStack {
                        Image(systemName: device.kind.symbolName)
                            .frame(width: 18).foregroundStyle(.secondary)
                        Toggle(isOn: visibility(for: device)) {
                            HStack(spacing: 6) {
                                Text(device.name).lineLimit(2)
                                if device.isUnpairedGhost {
                                    Text("未配对")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.secondary.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .onMove { source, destination in
                    var listed = devices
                    listed.move(fromOffsets: source, toOffset: destination)
                    preferences.update { $0.bluetoothDeviceOrder = listed.map(\.id) }
                }
            }
        } header: {
            Text("蓝牙设备列表")
        } footer: {
            Text("勾选显示并拖动排序；「未配对」是扫描残留，系统设置也不会列出。")
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("始终显示全部蓝牙设备", isOn: binding(\.alwaysShowsAllBluetoothDevices))
            LabeledContent("最多显示设备数") {
                HStack {
                    Text("\(preferences.configuration.bluetoothDeviceLimit)")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Stepper("最多显示设备数", value: binding(\.bluetoothDeviceLimit), in: 1 ... 20)
                        .labelsHidden()
                }
            }
            .disabled(preferences.configuration.alwaysShowsAllBluetoothDevices)
            Toggle("隐藏未配对设备", isOn: binding(\.hidesUnpairedBluetoothDevices))
        } header: {
            Text("面板显示")
        } footer: {
            Text("与系统设置的「我的设备」一致：未配对的扫描残留默认隐藏。")
        }
    }

    private var nearbySection: some View {
        Section {
            Toggle("扫描附近设备电量", isOn: nearbyScanBinding)
            if preferences.configuration.scansNearbyBluetoothDevices {
                switch scanner.authorization {
                case .allowedAlways, .notDetermined:
                    EmptyView()
                case .denied, .restricted:
                    Button("打开蓝牙隐私设置…") {
                        if let url = ProjectLinks.bluetoothPrivacy {
                            NSWorkspace.shared.open(url)
                        }
                    }
                @unknown default:
                    EmptyView()
                }
            }
        } header: {
            Text("附近设备")
        } footer: {
            Text("开启后申请蓝牙权限，每分钟扫描约 5 秒，读取附近设备的公开电量；不会配对或上传任何数据。")
        }
    }

    /// Turning the scan on starts the CoreBluetooth session right away, which
    /// is what surfaces the system authorization prompt in context.
    private var nearbyScanBinding: Binding<Bool> {
        Binding(get: { preferences.configuration.scansNearbyBluetoothDevices }, set: { enabled in
            preferences.update { $0.scansNearbyBluetoothDevices = enabled }
            if enabled {
                scanner.requestAccess()
            }
        })
    }

    private func visibility(for device: BluetoothDevice) -> Binding<Bool> {
        Binding(
            get: { !preferences.configuration.hiddenBluetoothDevices.contains(device.id) },
            set: { visible in
                preferences.update {
                    if visible {
                        $0.hiddenBluetoothDevices.remove(device.id)
                    } else {
                        $0.hiddenBluetoothDevices.insert(device.id)
                    }
                }
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
