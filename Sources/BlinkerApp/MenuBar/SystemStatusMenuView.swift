import SwiftUI

/// The existing context menu keeps both Blinker actions and readable system values.
struct SystemStatusMenuView: View {
    @ObservedObject var monitor: SystemStatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(
                "battery.100percent",
                label: String(localized: "电池"),
                value: monitor.snapshot.batteryDescription
            )
            row("network", label: String(localized: "网络"), value: monitor.snapshot.networkDescription)
            row("speaker.wave.2", label: String(localized: "音量"), value: monitor.snapshot.volumeDescription)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func row(_ symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16)
            Text(label)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

extension MenuBarSystemSnapshot {
    var batteryDescription: String {
        guard let battery else { return String(localized: "暂无电池信息") }
        let value = battery.percentage.map { "\(min(100, max(0, $0)))%" }
            ?? String(localized: "电量未知")
        let state: String? = if battery.isCharging {
            String(localized: "充电中")
        } else if battery.isConnectedToPower {
            String(localized: "已接电源")
        } else if battery.isLowPower {
            String(localized: "低电量模式")
        } else {
            nil
        }
        return [value, state].compactMap { $0 }.joined(separator: " · ")
    }

    var networkDescription: String {
        switch network {
        case .unknown: String(localized: "网络状态未知")
        case .off: String(localized: "Wi-Fi 已关闭")
        case .disconnected: String(localized: "Wi-Fi 未连接")
        case .wifi: String(localized: "Wi-Fi 已连接")
        case .wired: String(localized: "有线网络")
        case .personalHotspot: String(localized: "个人热点")
        case .temporary: String(localized: "临时连接")
        case .sharing: String(localized: "互联网共享")
        }
    }

    var volumeDescription: String {
        guard let volume else { return String(localized: "音量未知") }
        if volume.isMuted {
            return String(localized: "静音")
        }
        guard let scalar = volume.scalar, scalar.isFinite else { return String(localized: "音量未知") }
        return "\(Int((min(1, max(0, scalar)) * 100).rounded()))%"
    }

    var accessibilitySummary: String {
        var parts = [String(localized: "电池") + ": " + batteryDescription,
                     networkDescription,
                     String(localized: "音量") + ": " + volumeDescription]
        if inputMuted == true {
            parts.append(String(localized: "麦克风") + ": " + String(localized: "已静音"))
        }
        return parts.joined(separator: " · ")
    }
}
