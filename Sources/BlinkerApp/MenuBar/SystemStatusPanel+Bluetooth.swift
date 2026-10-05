import AppKit
import SwiftUI

/// The bluetooth block: paired devices with per-channel battery, folded with
/// the nearby BLE readings, plus the scan's permission guidance.
extension SystemStatusPanel {
    var bluetoothSection: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.rowSpacing) {
            heading("蓝牙", symbol: "antenna.radiowaves.left.and.right", page: .bluetooth)
            bluetoothContent
            if preferences.configuration.scansNearbyBluetoothDevices {
                nearbyContent
            }
            settingsLink("蓝牙设置…", destination: "com.apple.Bluetooth-Settings.extension")
        }
    }

    @ViewBuilder
    private var bluetoothContent: some View {
        let configuration = preferences.configuration
        if let devices = monitor.snapshot.bluetoothDevices {
            let merged = BluetoothNearbyMerge.merged(
                devices: devices,
                nearby: configuration.scansNearbyBluetoothDevices ? scanner.nearbyDevices : []
            )
            let listed = BluetoothDeviceOrdering
                .ordered(merged.devices, order: configuration.bluetoothDeviceOrder)
                .filter { !configuration.hiddenBluetoothDevices.contains($0.id) }
                .filter { !configuration.hidesUnpairedBluetoothDevices || !$0.isUnpairedGhost }
            if listed.isEmpty, merged.remainingNearby.isEmpty {
                Text("没有已配对的蓝牙设备。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let limit = expandedBluetoothDevices || configuration.alwaysShowsAllBluetoothDevices
                    ? listed.count : configuration.bluetoothDeviceLimit
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(listed.prefix(limit))) { device in
                        bluetoothRow(device)
                    }
                    if listed.count > configuration.bluetoothDeviceLimit,
                       !configuration.alwaysShowsAllBluetoothDevices {
                        Button(expandedBluetoothDevices
                            ? String(localized: "收起设备") : String(localized: "显示全部设备")) {
                            expandedBluetoothDevices.toggle()
                        }.buttonStyle(.borderless)
                    }
                }
            }
        } else {
            Text("正在读取…")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func bluetoothRow(_ device: BluetoothDevice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: device.kind.symbolName).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let subtitle = bluetoothSubtitle(device) {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            if let battery = device.battery {
                bluetoothBatteryView(battery)
            } else if !device.isConnected {
                Text("未连接")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if preferences.configuration.enablesBluetoothDeviceControl,
               scanner.authorization == .allowedAlways, device.isConnected {
                Button(String(localized: "断开")) { disconnect(device) }
                    .buttonStyle(.borderless).font(.caption)
                    .help("断开当前连接；设备保持已配对，可随时重新连接")
                    .accessibilityLabel(String(localized: "断开") + " " + device.name)
            }
        }
        .font(.callout)
        .foregroundStyle(device.isConnected ? .primary : .secondary)
        .accessibilityElement(children: .combine)
    }

    /// Codec requires the device-control opt-in and the Bluetooth grant;
    /// signal strength comes from the system report without any permission.
    private func bluetoothSubtitle(_ device: BluetoothDevice) -> String? {
        let configuration = preferences.configuration
        var parts: [String] = []
        if configuration.enablesBluetoothDeviceControl, let codec = device.audioCodec {
            parts.append(codec.rawValue)
        }
        if configuration.showsBluetoothSignalStrength, let rssi = device.rssi {
            parts.append("\(rssi) dBm")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The profiler cache holds the previous list for a few seconds, so the
    /// row is refreshed once quickly and again after the cache expires.
    private func disconnect(_ device: BluetoothDevice) {
        let address = device.id
        DispatchQueue.global(qos: .userInitiated).async {
            _ = BluetoothConnectionDetails.disconnect(address: address)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                monitor.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                monitor.refresh()
            }
        }
    }

    private func bluetoothBatteryView(_ battery: BluetoothDeviceBattery) -> some View {
        HStack(spacing: 4) {
            if let main = battery.main {
                Text("\(main)%")
            }
            if let left = battery.left {
                Text("L \(left)%")
            }
            if let right = battery.right {
                Text("R \(right)%")
            }
            if let caseLevel = battery.caseLevel {
                Label("\(caseLevel)%", systemImage: "airpods.chargingcase")
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var nearbyContent: some View {
        switch scanner.authorization {
        case .allowedAlways:
            let merged = BluetoothNearbyMerge.merged(
                devices: monitor.snapshot.bluetoothDevices ?? [],
                nearby: scanner.nearbyDevices
            )
            if !merged.remainingNearby.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(merged.remainingNearby) { device in
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right").frame(width: 18)
                            Text(device.name.isEmpty
                                ? String(localized: "未知设备") : device.name)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text("\(device.batteryLevel)%")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        case .notDetermined:
            Button {
                scanner.requestAccess()
            } label: {
                Label("允许蓝牙以显示附近设备电量", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        case .denied, .restricted:
            Button {
                if let url = ProjectLinks.bluetoothPrivacy {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("蓝牙权限已关闭，无法扫描附近设备", systemImage: "exclamationmark.shield")
                    .font(.callout)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        @unknown default:
            EmptyView()
        }
    }
}
