import AppKit
import SwiftUI

struct SystemStatusPanel: View {
    /// The two panel pages; quick actions lives apart from the status blocks.
    enum PanelPage: Hashable { case status, quickActions }

    @ObservedObject var monitor: SystemStatusMonitor
    @ObservedObject var audio: SystemAudioController
    @ObservedObject var scanner: BluetoothLEScanner
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var finderToggles: FinderTogglesController
    @ObservedObject var lowPower: LowPowerController
    let cleaning: CleaningWindowController
    let shortcutRunner: ShortcutRunner
    @ObservedObject var appearanceToggle: AppearanceToggleController
    @ObservedObject var displayModes: DisplayModesController
    @ObservedObject var screenActions: ScreenActionController
    let onOpenApplications: () -> Void
    let onOpenSettings: () -> Void
    let onOpenMenuBarPage: (MenuBarSettingsPage) -> Void
    var desktopActions: DesktopActionsCoordinator?
    var usesWindowToolbar = false
    @ObservedObject private var appPreferences = AppPreferences.shared
    @State private var expandedDevices = false
    @State private var expandedAudio = false
    @State private var page = PanelPage.status
    @State private var statusScroll = ScrollPosition(edge: .top)
    @State private var actionsScroll = ScrollPosition(edge: .top)
    @State var expandedBluetoothDevices = false
    @State var shortcutSlotStates: [String: ShortcutSlotState] = [:]
    @State var confirmingTrashEmpty = false
    @StateObject var ejector = VolumeEjectController()
    @StateObject var trashEmptier = TrashEmptyController()

    var body: some View {
        let density = preferences.configuration.panelDensity
        let showsQuickActions = preferences.configuration.enabledSections.contains(.quickActions)
        let activePage = showsQuickActions ? page : .status
        ScrollView {
            Group {
                if activePage == .status {
                    statusPage(density: density)
                } else {
                    quickActionsPage
                }
            }
            .padding(density.horizontalPadding)
        }
        .id(activePage)
        .scrollPosition(activePage == .status ? $statusScroll : $actionsScroll)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 460)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !usesWindowToolbar {
                HStack(spacing: 12) {
                    pageNavigation
                    Spacer(minLength: 0)
                    managementMenu
                        .controlSize(.regular)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                }
                .padding(.horizontal, density.horizontalPadding)
                .padding(.vertical, density.headerPadding)
            }
        }
        .toolbar {
            if usesWindowToolbar {
                ToolbarItem(placement: .principal) {
                    pageNavigation
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    managementMenu
                }
            }
        }
        .background { PanelSurface(usesWindowToolbar: usesWindowToolbar) }
        .preferredColorScheme(appPreferences.appearance.resolvedScheme)
        .frame(width: 360)
        .controlSize(.regular)
        .toggleStyle(.switch)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: monitor.snapshot.storage) { _, newValue in
            ejector.prune(keeping: newValue?.external ?? [])
        }
    }

    private func statusPage(density: MenuBarConfiguration.PanelDensity) -> some View {
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            ForEach(preferences.configuration.visibleSections, id: \.self) { section in
                Group {
                    switch section {
                    case .battery: batterySection
                    case .network: networkSection
                    case .volume: volumeSection
                    case .bluetooth: bluetoothSection
                    case .storage: storageSection
                    case .performance: performanceSection
                    case .quickActions: EmptyView()
                    }
                }
                .modifier(StatusPanelGroup())
            }
            if preferences.configuration.visibleSections.isEmpty {
                Text("所有状态区块均已隐藏，可在面板布局中重新开启。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = audio.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if preferences.configuration.showsBatteryDetails,
                       let details = monitor.snapshot.batteryDetails {
                        batteryDetailsRows(details)
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    settingsLink("打开系统电池设置…", destination: "com.apple.Battery-Settings.extension")
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    heading("电池", symbol: "battery.100percent", page: .battery)
                    Text(monitor.snapshot.batteryDescription)
                        .font(.title3.weight(.medium)).monospacedDigit()
                }
            }
            if let value = monitor.snapshot.battery?.percentage {
                ProgressView(value: Double(value), total: 100).tint(batteryColor)
                    .accessibilityLabel("电量").accessibilityValue("\(value)%")
            }
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
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if case let .wifi(strength) = monitor.snapshot.network {
                        Label(strength == 3 ? String(localized: "信号强")
                            : strength == 2 ? String(localized: "信号中等") : String(localized: "信号弱"),
                            systemImage: "wifi")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    networkDetailRows
                    settingsLink("打开系统网络设置…", destination: "com.apple.Network-Settings.extension")
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    heading("网络", symbol: "wifi", page: .network)
                    Text(monitor.snapshot.networkDescription).font(.callout).foregroundStyle(.secondary)
                }
            }
            networkActivityRow
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.rowSpacing) {
            heading("音量", symbol: "speaker.wave.2", page: .audio)
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
            DisclosureGroup(isExpanded: $expandedAudio) {
                outputDevices
                if preferences.configuration.showsAudioInput, let input = audio.input {
                    inputRow(input)
                }
                settingsLink("打开系统声音设置…", destination: "com.apple.Sound-Settings.extension")
            } label: {
                Text(expandedAudio ? String(localized: "输出设备")
                    : audio.outputs.first(where: { $0.id == audio.currentDeviceID })?.name
                        ?? String(localized: "输出设备"))
                    .lineLimit(2)
            }
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

    private var displayedOutputDevices: [SystemAudioOutput] {
        let config = preferences.configuration
        let limit = expandedDevices || config.alwaysShowsAllOutputDevices
            ? orderedDevices.count : config.outputDeviceLimit
        return Array(orderedDevices.prefix(limit))
    }

    private var outputDevices: some View {
        let configuration = preferences.configuration
        let all = orderedDevices
        return VStack(alignment: .leading, spacing: preferences.configuration.panelDensity.rowSpacing) {
            if all.isEmpty {
                if audio.isBusy {
                    OperationProgress(message: String(localized: "正在读取输出设备…"))
                } else if audio.errorMessage == nil {
                    Text("暂无可用的输出设备").foregroundStyle(.secondary)
                }
            }
            if !all.isEmpty {
                Picker("输出设备", selection: Binding(
                    get: { audio.currentDeviceID },
                    set: { if let deviceID = $0 { audio.selectOutput(deviceID) } }
                )) {
                    if audio.currentDeviceID == nil {
                        Text("暂无可用的输出设备").tag(Optional<UInt32>.none)
                    }
                    ForEach(all.filter { device in
                        displayedOutputDevices.contains { $0.id == device.id }
                            || device.id == audio.currentDeviceID
                    }) { device in
                        Label(device.name, systemImage: device.isBluetooth ? "headphones" : "speaker.wave.2")
                            .tag(Optional(device.id))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(audio.isBusy)
            }
            if all.count > configuration.outputDeviceLimit, !configuration.alwaysShowsAllOutputDevices {
                Button(expandedDevices ? String(localized: "收起设备") : String(localized: "显示全部设备")) {
                    expandedDevices.toggle()
                }.buttonStyle(.borderless)
            }
        }
        .background(MenuBarPanelRegion(identifier: "BlinkerAudioDeviceList"))
    }
}

extension SystemStatusPanel {
    private var pageNavigation: some View {
        StatusPanelHeader(page: $page,
                          showsQuickActions: preferences.configuration.enabledSections
                              .contains(.quickActions))
    }

    private var managementMenu: some View {
        Menu {
            Button("刷新", systemImage: "arrow.clockwise") { refreshPanel() }
                .disabled(audio.isBusy)
            Divider()
            Button("应用规则", systemImage: "macwindow", action: onOpenApplications)
            Button("设置…", systemImage: "gearshape", action: onOpenSettings)
            Section("自定义…") {
                Button("面板布局") { onOpenMenuBarPage(.panel) }
                Button("快速操作") { onOpenMenuBarPage(.quickActions) }
                Menu("状态") {
                    ForEach(preferences.configuration.visibleSections, id: \.self) { section in
                        Button(section.title) {
                            onOpenMenuBarPage(settingsPage(for: section))
                        }
                    }
                }
            }
        } label: {
            Label("管理面板", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .help("管理面板")
    }

    private func refreshPanel() {
        monitor.refresh()
        audio.refresh()
        scanner.refresh()
        if page == .quickActions {
            finderToggles.refresh()
            lowPower.refresh()
            appearanceToggle.refresh()
            displayModes.refresh()
        }
    }

    private func settingsPage(for section: MenuBarConfiguration.Section) -> MenuBarSettingsPage {
        switch section {
        case .battery: .battery
        case .network: .network
        case .volume: .audio
        case .bluetooth: .bluetooth
        case .storage: .storage
        case .performance: .performance
        case .quickActions: .quickActions
        }
    }

}

extension SystemStatusPanel {
    func heading(_ title: LocalizedStringKey, symbol: String,
                 page _: MenuBarSettingsPage) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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
