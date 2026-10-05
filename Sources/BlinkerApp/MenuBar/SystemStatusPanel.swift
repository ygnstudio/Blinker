import AppKit
import SwiftUI

struct SystemStatusPanel: View {
    @ObservedObject var monitor: SystemStatusMonitor
    @ObservedObject var audio: SystemAudioController
    @ObservedObject var scanner: BluetoothLEScanner
    @ObservedObject var preferences: MenuBarPreferences
    let onOpenApplications: () -> Void
    let onOpenSettings: () -> Void
    let onOpenMenuBarPage: (MenuBarSettingsPage) -> Void
    @State private var expandedDevices = false
    @State var expandedBluetoothDevices = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("系统状态").font(.headline)
                Spacer()
                if audio.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("刷新", systemImage: "arrow.clockwise") {
                    monitor.refresh()
                    audio.refresh()
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(preferences.configuration.visibleSections, id: \.self) { section in
                        switch section {
                        case .battery: batterySection
                        case .network: networkSection
                        case .volume: volumeSection
                        case .bluetooth: bluetoothSection
                        }
                    }
                    if preferences.configuration.visibleSections.isEmpty {
                        Text("所有状态区块均已隐藏，可在状态图标设置中重新开启。")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = audio.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 460)
            Divider()
            HStack {
                Button("应用规则", action: onOpenApplications)
                Spacer()
                Button("状态图标设置…", action: onOpenSettings)
            }
            .buttonStyle(.borderless).padding(14)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("电池", symbol: "battery.100percent", page: .battery)
            Text(monitor.snapshot.batteryDescription).font(.title3).monospacedDigit()
            if let value = monitor.snapshot.battery?.percentage {
                ProgressView(value: Double(value), total: 100).tint(batteryColor)
                    .accessibilityLabel("电量").accessibilityValue("\(value)%")
            }
            settingsLink("电池设置…", destination: "com.apple.Battery-Settings.extension")
        }
    }

    private var batteryColor: Color {
        guard let battery = monitor.snapshot.battery else { return .secondary }
        if let value = battery.percentage,
           Double(value) < preferences.configuration.batteryCriticalThreshold {
            return .red
        }
        if battery.isLowPower {
            return .yellow
        }
        return battery.isCharging || battery.isConnectedToPower ? .green : .accentColor
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("网络", symbol: "network", page: .networkAndVolume)
            Text(monitor.snapshot.networkDescription)
            if case let .wifi(strength) = monitor.snapshot.network {
                Label(strength == 3 ? String(localized: "信号强")
                    : strength == 2 ? String(localized: "信号中等") : String(localized: "信号弱"),
                    systemImage: "wifi")
                    .foregroundStyle(.secondary).font(.callout)
            }
            if preferences.configuration.showsWiFiName {
                wifiNameRow
            }
            if preferences.configuration.showsVPNStatus, let vpn = monitor.snapshot.vpn {
                vpnRow(vpn)
            }
            settingsLink("网络设置…", destination: "com.apple.Network-Settings.extension")
        }
    }

    @ViewBuilder
    private var wifiNameRow: some View {
        if let name = monitor.snapshot.wifiName {
            Label(name, systemImage: "wifi")
                .foregroundStyle(.secondary).font(.callout).lineLimit(2)
        } else {
            switch monitor.wiFiNameAccess {
            case .authorized:
                EmptyView()
            case .notDetermined:
                Button {
                    handleWiFiNameAccess(monitor.requestWiFiNameAccess())
                } label: {
                    Label("允许定位以显示 Wi-Fi 名称", systemImage: "location")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            case .denied, .restricted:
                Button {
                    openLocationSettings()
                } label: {
                    Label("定位已关闭，无法显示 Wi-Fi 名称", systemImage: "location.slash")
                        .font(.callout)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }

    private func handleWiFiNameAccess(_ result: WiFiNameAccessRequestResult) {
        if result == .openLocationSettings {
            openLocationSettings()
        }
    }

    private func openLocationSettings() {
        guard let url = ProjectLinks.locationPrivacy else { return }
        NSWorkspace.shared.open(url)
    }

    private func vpnRow(_ vpn: MenuBarSystemSnapshot.VPN) -> some View {
        HStack(spacing: 6) {
            Image(systemName: vpn.isTunnelConnected ? "lock.shield" : "network.badge.shield.half.filled")
                .frame(width: 18)
            if let service = vpn.serviceName {
                Text("VPN：\(service)").lineLimit(2)
            } else if vpn.isTunnelConnected {
                Text("VPN：已连接")
            } else if let endpoint = vpn.proxyEndpoint {
                Text("代理：\(endpoint)").lineLimit(2)
            }
        }
        .foregroundStyle(.secondary).font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("音量", symbol: "speaker.wave.2", page: .panel)
            if let device = audio.outputs.first(where: { $0.id == audio.currentDeviceID }) {
                Text(device.name).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityLabel(String(localized: "当前输出设备") + " " + device.name)
            }
            HStack(spacing: 10) {
                Button {
                    audio.setMuted(!audio.isMuted)
                } label: {
                    Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless).disabled(!audio.canMute)
                .accessibilityLabel(audio.isMuted ? String(localized: "取消静音") : String(localized: "静音"))
                Slider(value: Binding(get: { audio.volume ?? 0 }, set: { audio.setVolume($0) }), in: 0 ... 1)
                    .disabled(!audio.canSetVolume).accessibilityLabel("输出音量")
                Text(audio.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .monospacedDigit().frame(minWidth: 38, alignment: .trailing)
            }
            .background(MenuBarPanelRegion(identifier: "BlinkerVolumeControl"))
            if !audio.canSetVolume {
                Text("此输出设备不提供系统音量控制。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            outputDevices
            if preferences.configuration.showsAudioInput, let input = audio.input {
                inputRow(input)
            }
            settingsLink("声音设置…", destination: "com.apple.Sound-Settings.extension")
        }
    }

    private func inputRow(_ input: SystemAudioInput) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mic").frame(width: 18)
                Text(input.name).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if input.isInUse {
                    Text("使用中")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    audio.setInputMuted(!input.isMuted)
                } label: {
                    Image(systemName: input.isMuted ? "mic.slash.fill" : "mic.fill")
                }
                .buttonStyle(.borderless).disabled(!input.canMute)
                .accessibilityLabel(input.isMuted ? String(localized: "取消输入静音")
                    : String(localized: "输入静音"))
                Slider(value: Binding(get: { input.volume ?? 0 },
                                      set: { audio.setInputVolume($0) }), in: 0 ... 1)
                    .disabled(!input.canSetVolume).accessibilityLabel("输入音量")
                Text(input.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .monospacedDigit().frame(minWidth: 38, alignment: .trailing)
            }
            if !input.canSetVolume, !input.canMute {
                Text("此输入设备不提供系统音量控制。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(String(localized: "当前输入设备") + " " + input.name)
    }

    private var orderedDevices: [SystemAudioOutput] {
        let order = preferences.configuration.outputDeviceOrder
        return audio.outputs.enumerated().sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.element.uid) ?? (order.count + lhs.offset)
            let right = order.firstIndex(of: rhs.element.uid) ?? (order.count + rhs.offset)
            return left < right
        }.map(\.element)
    }

    private var outputDevices: some View {
        let configuration = preferences.configuration
        let all = orderedDevices
        let limit = expandedDevices || configuration.alwaysShowsAllOutputDevices
            ? all.count : configuration.outputDeviceLimit
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(all.prefix(limit))) { device in
                Button { audio.selectOutput(device.id) } label: {
                    HStack {
                        Image(systemName: device.isBluetooth ? "headphones" : "speaker.wave.2")
                            .frame(width: 18)
                        Text(device.name).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if audio.currentDeviceID == device.id {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle()).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityValue(audio.currentDeviceID == device.id ? String(localized: "当前输出设备") : "")
            }
            if all.count > configuration.outputDeviceLimit, !configuration.alwaysShowsAllOutputDevices {
                Button(expandedDevices ? String(localized: "收起设备") : String(localized: "显示全部设备")) {
                    expandedDevices.toggle()
                }.buttonStyle(.borderless)
            }
        }
        .background(MenuBarPanelRegion(identifier: "BlinkerAudioDeviceList"))
    }

    func heading(_ title: LocalizedStringKey, symbol: String,
                 page: MenuBarSettingsPage) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.callout.weight(.semibold))
            Spacer()
            Button { onOpenMenuBarPage(page) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .help("打开相关设置")
            .accessibilityLabel(String(localized: "打开相关设置"))
        }
    }

    func settingsLink(_ title: LocalizedStringKey, destination: String) -> some View {
        Button(title) {
            if let url = URL(string: "x-apple.systempreferences:" + destination) {
                NSWorkspace.shared.open(url)
            }
        }.buttonStyle(.borderless).font(.callout)
    }
}

private struct MenuBarPanelRegion: NSViewRepresentable {
    let identifier: String
    func makeNSView(context _: Context) -> NSView {
        let view = MarkerView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class MarkerView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
