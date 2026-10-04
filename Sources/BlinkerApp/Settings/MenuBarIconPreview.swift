import AppKit
import SwiftUI

/// Uses the production renderers; only the selected scenario and backdrop are simulated.
struct MenuBarIconPreview: View {
    let configuration: MenuBarConfiguration
    let snapshot: MenuBarSystemSnapshot
    @State private var scenario = MenuBarPreviewScenario.live
    @State private var darkBackground = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("图标预览").font(.headline)
                    Spacer()
                    Picker("预览状态", selection: $scenario) {
                        ForEach(MenuBarPreviewScenario.allCases, id: \.self) { scenario in
                            Text(scenario.title).tag(scenario)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                }
                HStack(spacing: 16) {
                    sample(title: String(localized: "实际尺寸")) { animatedIcon(size: actualIconSize) }
                    sample(title: String(localized: "放大示意（仅预览）")) { animatedIcon(size: 72) }
                    sample(title: String(localized: "Dock 预览")) {
                        Image(nsImage: DockIconRenderer.image(snapshot: displayedSnapshot,
                                                              configuration: configuration,
                                                              appearance: appearance))
                            .resizable().interpolation(.high).frame(width: 72, height: 72)
                    }
                }
                .padding(10)
                .background(darkBackground ? Color(white: 0.16) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Toggle("深色预览背景", isOn: $darkBackground).toggleStyle(.checkbox)
                    Spacer()
                    Text(scenario == .live ? String(localized: "使用当前状态")
                        : String(localized: "模拟数据，仅用于预览"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    private var displayedSnapshot: MenuBarSystemSnapshot {
        scenario.snapshot(live: snapshot)
    }

    private var appearance: NSAppearance? {
        NSAppearance(named: darkBackground ? .darkAqua : .aqua)
    }

    private var actualIconSize: CGFloat {
        min(configuration.iconSize, max(16, NSStatusBar.system.thickness - 2))
    }

    private func animatedIcon(size: CGFloat) -> some View {
        MenuBarAnimatedIcon(snapshot: displayedSnapshot, configuration: configuration,
                            size: size, appearance: appearance)
            .frame(width: size, height: size)
    }

    private func sample(title: String, @ViewBuilder graphic: () -> some View) -> some View {
        VStack(spacing: 4) {
            graphic()
                .frame(height: 72)
                .accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(darkBackground ? Color.white : Color.black)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(displayedSnapshot.accessibilitySummary)
    }
}

private enum MenuBarPreviewScenario: CaseIterable, Hashable {
    case live, battery, charging, lowBattery, lowPower, wired, muted, bluetooth, bluetoothOffline, unavailable

    var title: String {
        switch self {
        case .live: String(localized: "当前状态")
        case .battery: String(localized: "模拟：电池供电")
        case .charging: String(localized: "模拟：充电")
        case .lowBattery: String(localized: "模拟：低电量")
        case .lowPower: String(localized: "模拟：低电量模式")
        case .wired: String(localized: "模拟：有线连接")
        case .muted: String(localized: "模拟：静音")
        case .bluetooth: String(localized: "模拟：蓝牙音频")
        case .bluetoothOffline: String(localized: "模拟：蓝牙音频与断网")
        case .unavailable: String(localized: "模拟：状态未知")
        }
    }

    func snapshot(live: MenuBarSystemSnapshot) -> MenuBarSystemSnapshot {
        guard self != .live else { return live }
        guard self != .unavailable else { return .unknown }
        return MenuBarSystemSnapshot(
            battery: .init(percentage: self == .lowBattery ? 10 : 65,
                           isCharging: self == .charging,
                           isConnectedToPower: self == .charging,
                           isLowPower: self == .lowPower),
            network: self == .wired ? .wired :
                (self == .bluetoothOffline ? .disconnected : .wifi(strength: 3)),
            volume: .init(scalar: 0.5, isMuted: self == .muted,
                          isBluetooth: self == .bluetooth || self == .bluetoothOffline,
                          symbolName: "headphones")
        )
    }
}
