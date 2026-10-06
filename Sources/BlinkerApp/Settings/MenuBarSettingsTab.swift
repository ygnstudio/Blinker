import AppKit
import SwiftUI

struct MenuBarSettingsTab: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var monitor: SystemStatusMonitor
    @ObservedObject var audio: SystemAudioController
    @ObservedObject var scanner: BluetoothLEScanner
    @ObservedObject var navigation: SettingsNavigation
    @State private var confirmingReset = false

    init(preferences: MenuBarPreferences? = nil, monitor: SystemStatusMonitor,
         audio: SystemAudioController, scanner: BluetoothLEScanner,
         navigation: SettingsNavigation) {
        self.preferences = preferences ?? .shared
        self.monitor = monitor
        self.audio = audio
        self.scanner = scanner
        self.navigation = navigation
    }

    var body: some View {
        VStack(spacing: 0) {
            if navigation.menuBarPage != .panel {
                MenuBarIconPreview(configuration: configuration, snapshot: monitor.snapshot)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            Picker("状态图标设置分类", selection: $navigation.menuBarPage) {
                ForEach(MenuBarSettingsPage.allCases, id: \.self) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Form {
                switch navigation.menuBarPage {
                case .icon: iconSettings
                case .battery: batterySettings
                case .networkAndVolume:
                    networkSettings
                    MenuBarAudioSettings(preferences: preferences)
                case .bluetooth:
                    MenuBarBluetoothSettings(preferences: preferences, monitor: monitor,
                                             scanner: scanner)
                case .quickActions:
                    MenuBarQuickActionsSettings(preferences: preferences, monitor: monitor)
                case .panel: MenuBarPanelSettings(preferences: preferences, audio: audio)
                case .storage: MenuBarStorageSettings(preferences: preferences)
                case .performance: MenuBarPerformanceSettings(preferences: preferences)
                }
                Section {
                    Button("恢复状态图标默认设置…") { confirmingReset = true }
                        .disabled(configuration == MenuBarConfiguration())
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog("恢复状态图标默认设置？", isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button("恢复默认设置", role: .destructive) { preferences.reset() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将重置显示位置、图标、状态面板和音量交互的自定义设置。")
        }
    }

    private var configuration: MenuBarConfiguration {
        preferences.configuration
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }

    @ViewBuilder
    private var iconSettings: some View {
        Section {
            MenuBarOptionCardGroup(
                label: String(localized: "显示位置"),
                options: MenuBarConfiguration.Placement.allCases,
                selection: configuration.placement,
                title: { $0.title },
                image: placementImage,
                onSelect: { choice in preferences.update { $0.placement = choice } }
            )
            MenuBarOptionCardGroup(
                label: String(localized: "线条粗细"),
                options: MenuBarConfiguration.Stroke.allCases,
                selection: configuration.stroke,
                title: { $0.title },
                image: strokeImage,
                onSelect: { choice in preferences.update { $0.stroke = choice } }
            )
        } header: {
            Text("图标外观")
        }
        Section {
            SliderReadoutRow(label: String(localized: "菜单栏图标大小"),
                             readout: "\(Int(configuration.iconSize)) pt",
                             value: binding(\.iconSize), range: 16 ... 36, step: 1)
                .disabled(!configuration.showsMenuBar)
            Picker("菜单栏单击", selection: binding(\.leftClick)) {
                ForEach(MenuBarConfiguration.ClickAction.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .disabled(!configuration.showsMenuBar)
        } header: {
            Text("菜单栏")
        } footer: {
            Text("图标大小受系统菜单栏高度限制。右键打开应用规则、设置和暂停菜单。")
        }
        Section {
            MenuBarOptionCardGroup(
                label: String(localized: "Dock 图标背景"),
                options: MenuBarConfiguration.DockBackground.allCases,
                selection: configuration.dockBackground,
                title: { $0.title },
                image: dockBackgroundImage,
                onSelect: { choice in preferences.update { $0.dockBackground = choice } }
            )
            .disabled(!configuration.showsDock)
        } header: {
            Text("Dock")
        } footer: {
            Text("点击 Blinker 的 Dock 图标打开状态面板。预览背景不会改变 Dock 图标或系统外观。")
        }
        Section {
            SliderReadoutRow(label: String(localized: "状态刷新间隔"),
                             readout: String(localized: "\(Int(configuration.refreshInterval)) 秒"),
                             value: binding(\.refreshInterval), range: 5 ... 60, step: 5)
        } header: {
            Text("状态刷新")
        } footer: {
            Text("状态变化会自动刷新，此间隔用于定期补充检查。")
        }
    }

    @ViewBuilder
    private var batterySettings: some View {
        Section("电量显示") {
            Toggle("显示电量百分比", isOn: binding(\.showsBatteryPercentage))
            Toggle("在图标中央显示电量", isOn: binding(\.showsBatteryInCenter))
                .help("用电量数字替代中央网络图形。")
            Toggle("显示充电与电源标记", isOn: binding(\.showsChargingIndicator))
            Toggle("接电未充电时显示百分比", isOn: binding(\.showsPercentageWhenConnected))
                .disabled(!configuration.showsBatteryPercentage || !configuration.showsChargingIndicator)
            SliderReadoutRow(label: String(localized: "电池标记大小"),
                             readout: percent(configuration.batterySymbolScale),
                             value: binding(\.batterySymbolScale), range: 0.5 ... 2, step: 0.05)
        }
        Section {
            Toggle("使用电池状态颜色", isOn: binding(\.usesBatteryColors))
            SliderReadoutRow(label: String(localized: "低电量阈值"),
                             readout: "\(Int(configuration.batteryCriticalThreshold))%",
                             value: binding(\.batteryCriticalThreshold), range: 0 ... 100, step: 1)
                .disabled(!configuration.usesBatteryColors)
        } header: {
            Text("电池颜色")
        } footer: {
            Text("低于阈值时显示红色；否则，低电量模式显示黄色，充电或接电显示绿色。")
        }
        Section {
            Toggle("菜单栏充电光效", isOn: binding(\.showsChargingEffect))
            Toggle("闪电呼吸", isOn: binding(\.showsChargingHeartbeat))
                .disabled(!configuration.showsChargingEffect || !configuration.showsChargingIndicator)
        } header: {
            Text("充电效果")
        } footer: {
            Text("仅在充电时播放；减少动态效果、低电量模式或屏幕休眠时停用动画。")
        }
        Section {
            Toggle("显示电池详情", isOn: binding(\.showsBatteryDetails))
        } header: {
            Text("面板电池区块")
        } footer: {
            Text("循环次数、健康度、温度与充放功率读取自电池控制器；无内置电池的机型不显示。")
        }
    }

    @ViewBuilder
    private var networkSettings: some View {
        Section {
            SliderReadoutRow(label: String(localized: "Wi-Fi 图形大小"),
                             readout: percent(configuration.wifiSymbolScale),
                             value: binding(\.wifiSymbolScale), range: 1 ... 1.8, step: 0.05)
            Toggle("有线连接也使用 Wi-Fi 图形", isOn: binding(\.showsWiFiForWired))
            Toggle("个人热点使用 Wi-Fi 图形", isOn: binding(\.showsWiFiForHotspot))
            Toggle("临时连接使用 Wi-Fi 图形", isOn: binding(\.showsWiFiForTemporary))
            Toggle("互联网共享使用 Wi-Fi 图形", isOn: binding(\.showsWiFiForSharing))
        } header: {
            Text("网络图形")
        } footer: {
            Text("开启替换后，对应连接类型显示普通 Wi-Fi 图形而非专用标记。中央电量显示开启且电量可用时，电量数字会替代网络或蓝牙图形。")
        }
        Section {
            Toggle("蓝牙音频替代网络图形", isOn: binding(\.replacesNetworkWithBluetooth))
            Toggle("优先显示网络异常", isOn: binding(\.prioritizesNetworkErrors))
                .disabled(!configuration.replacesNetworkWithBluetooth)
            SliderReadoutRow(label: String(localized: "蓝牙图形大小"),
                             readout: percent(configuration.bluetoothSymbolScale),
                             value: binding(\.bluetoothSymbolScale), range: 1 ... 1.8, step: 0.05)
                .disabled(!configuration.replacesNetworkWithBluetooth)
        } header: {
            Text("蓝牙音频图形")
        } footer: {
            Text("当前音频输出为蓝牙设备时，在图标中央显示设备图形。")
        }
        Section {
            Toggle("显示 VPN 状态", isOn: binding(\.showsVPNStatus))
            Toggle("显示 Wi-Fi 名称", isOn: wiFiNameBinding)
            Toggle("显示实时上下行速率", isOn: binding(\.showsNetworkActivity))
            Toggle("显示本机 IP", isOn: binding(\.showsLocalIPAddress))
            Toggle("显示公网 IP", isOn: binding(\.showsPublicIPAddress))
        } header: {
            Text("面板网络区块")
        } footer: {
            Text("Wi-Fi 名称需要定位权限来解除系统对网络名称的隐藏；Blinker 不读取位置本身。VPN 行在检测到隧道或系统代理时显示。"
                 + "速率为两次刷新间的平均值；公网 IP 通过 api.ipify.org 查询，仅在开启时发起请求。")
        }
    }

    /// Turning the row on kicks off the authorization flow right away, so the
    /// user sees the system prompt in context instead of discovering it later.
    private var wiFiNameBinding: Binding<Bool> {
        Binding(get: { configuration.showsWiFiName }, set: { enabled in
            preferences.update { $0.showsWiFiName = enabled }
            guard enabled,
                  monitor.requestWiFiNameAccess() == .openLocationSettings,
                  let url = ProjectLinks.locationPrivacy else { return }
            NSWorkspace.shared.open(url)
        })
    }

    private func glyphImage(_ change: (inout MenuBarConfiguration) -> Void) -> NSImage {
        var value = configuration
        change(&value)
        return TrioIconRenderer.image(snapshot: .optionCardPreview, size: 44,
                                      appearance: nil, configuration: value)
    }

    private func placementImage(_ placement: MenuBarConfiguration.Placement) -> NSImage {
        switch placement {
        case .menuBar:
            return glyphImage { _ in }
        case .dock:
            return DockIconRenderer.image(snapshot: .optionCardPreview, configuration: configuration)
        case .both:
            let menuBar = glyphImage { _ in }
            let dock = DockIconRenderer.image(snapshot: .optionCardPreview, configuration: configuration)
            return NSImage(size: NSSize(width: 96, height: 44), flipped: false) { _ in
                menuBar.draw(in: CGRect(x: 0, y: 0, width: 44, height: 44))
                dock.draw(in: CGRect(x: 52, y: 0, width: 44, height: 44))
                return true
            }
        }
    }

    private func strokeImage(_ stroke: MenuBarConfiguration.Stroke) -> NSImage {
        glyphImage { $0.stroke = stroke }
    }

    private func dockBackgroundImage(_ background: MenuBarConfiguration.DockBackground) -> NSImage {
        var value = configuration
        value.dockBackground = background
        return DockIconRenderer.image(snapshot: .optionCardPreview, configuration: value)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

enum MenuBarSettingsPage: CaseIterable, Hashable {
    case icon, battery, networkAndVolume, bluetooth, quickActions, panel, storage, performance

    var title: String {
        switch self {
        case .icon: String(localized: "图标")
        case .battery: String(localized: "电池")
        case .networkAndVolume: String(localized: "网络与音量")
        case .bluetooth: String(localized: "蓝牙")
        case .quickActions: String(localized: "快速操作")
        case .panel: String(localized: "状态面板")
        case .storage: String(localized: "存储")
        case .performance: String(localized: "性能")
        }
    }
}
