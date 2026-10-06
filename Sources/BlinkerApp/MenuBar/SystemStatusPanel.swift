import AppKit
import SwiftUI

struct SystemStatusPanel: View {
    /// The two panel pages; quick actions lives apart from the status blocks.
    enum PanelPage { case status, quickActions }

    @ObservedObject var monitor: SystemStatusMonitor
    @ObservedObject var audio: SystemAudioController
    @ObservedObject var scanner: BluetoothLEScanner
    @ObservedObject var preferences: MenuBarPreferences
    let cleaning: CleaningWindowController
    let shortcutRunner: ShortcutRunner
    let onOpenApplications: () -> Void
    let onOpenSettings: () -> Void
    let onOpenMenuBarPage: (MenuBarSettingsPage) -> Void
    @State private var expandedDevices = false
    @State private var page = PanelPage.status
    @State var expandedBluetoothDevices = false
    @State var shortcutSlotStates: [String: ShortcutSlotState] = [:]
    @State var confirmingTrashEmpty = false
    @StateObject var ejector = VolumeEjectController()
    @StateObject var trashEmptier = TrashEmptyController()

    var body: some View {
        let density = preferences.configuration.panelDensity
        let showsQuickActions = preferences.configuration.enabledSections.contains(.quickActions)
        let activePage = showsQuickActions ? page : .status
        VStack(spacing: 0) {
            HStack {
                Text(activePage == .status ? "系统状态" : "快速操作").font(.headline)
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
            .padding(density.headerPadding)
            if showsQuickActions {
                Picker("", selection: $page) {
                    Text("状态").tag(PanelPage.status)
                    Text("快速操作").tag(PanelPage.quickActions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, density.horizontalPadding)
                .padding(.bottom, 8)
            }
            ScrollView {
                Group {
                    if activePage == .status {
                        statusPage(density: density)
                    } else {
                        quickActionsPage
                    }
                }
                .padding(.horizontal, density.horizontalPadding)
                .padding(.bottom, density.horizontalPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 460)
            Divider()
            HStack {
                Button("应用规则", action: onOpenApplications)
                Spacer()
                Button("状态图标设置…", action: onOpenSettings)
            }
            .buttonStyle(.borderless).padding(density.footerPadding)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: monitor.snapshot.storage) { _, newValue in
            ejector.prune(keeping: newValue?.external ?? [])
        }
    }

    private func statusPage(density: MenuBarConfiguration.PanelDensity) -> some View {
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            ForEach(preferences.configuration.visibleSections, id: \.self) { section in
                switch section {
                case .battery: batterySection
                case .network: networkSection
                case .volume: volumeSection
                case .bluetooth: bluetoothSection
                case .storage: storageSection
                case .performance: performanceSection
                // Unreachable: visibleSections lists status blocks only.
                case .quickActions: EmptyView()
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
    }

    private var batterySection: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.rowSpacing) {
            heading("电池", symbol: "battery.100percent", page: .battery)
            Text(monitor.snapshot.batteryDescription).font(.title3).monospacedDigit()
            if let value = monitor.snapshot.battery?.percentage {
                ProgressView(value: Double(value), total: 100).tint(batteryColor)
                    .accessibilityLabel("电量").accessibilityValue("\(value)%")
            }
            if preferences.configuration.showsBatteryDetails,
               let details = monitor.snapshot.batteryDetails {
                batteryDetailsRows(details)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
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
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.rowSpacing) {
            heading("网络", symbol: "network", page: .networkAndVolume)
            Text(monitor.snapshot.networkDescription)
            if case let .wifi(strength) = monitor.snapshot.network {
                Label(strength == 3 ? String(localized: "信号强")
                    : strength == 2 ? String(localized: "信号中等") : String(localized: "信号弱"),
                    systemImage: "wifi")
                    .foregroundStyle(.secondary).font(.callout)
            }
            networkDetailRows
            settingsLink("网络设置…", destination: "com.apple.Network-Settings.extension")
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.rowSpacing) {
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
