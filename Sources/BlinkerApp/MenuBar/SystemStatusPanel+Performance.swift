import AppKit
import SwiftUI

/// The performance block: CPU load averaged over the refresh interval,
/// memory used vs. total, swap and uptime. Every row has its own settings
/// toggle; CPU stays hidden until two samples exist.
extension SystemStatusPanel {
    @ViewBuilder
    var performanceSection: some View {
        let configuration = preferences.configuration
        VStack(alignment: .leading,
               spacing: configuration.panelDensity.rowSpacing) {
            heading("性能", symbol: "gauge.with.dots.needle.67percent", page: .performance)
            if configuration.showsCPULoad, let usage = monitor.snapshot.performance?.cpuUsage {
                Label(String(localized: "CPU \(Int((usage * 100).rounded()))%"),
                      systemImage: "cpu")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(String(localized: "CPU 使用率"))
            }
            if configuration.showsMemoryUsage, let memory = monitor.snapshot.performance?.memory {
                let used = SystemStorageInfo.formatBytes(memory.usedBytes)
                let total = SystemStorageInfo.formatBytes(memory.totalBytes)
                Label(String(localized: "内存 \(used) / \(total)"),
                      systemImage: "memorychip")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(String(localized: "内存用量"))
            }
            if configuration.showsSwapUsage, let swap = monitor.snapshot.performance?.swapUsedBytes {
                Label(String(localized: "交换 \(SystemStorageInfo.formatBytes(swap))"),
                      systemImage: "arrow.left.arrow.right")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(String(localized: "交换空间用量"))
            }
            if configuration.showsUptime, let performance = monitor.snapshot.performance {
                Label(String(localized: "已运行 \(SystemPerformance.formatUptime(performance.uptime))"),
                      systemImage: "clock")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Button("打开活动监视器") {
                NSWorkspace.shared.open(URL(
                    fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            .buttonStyle(.borderless).font(.callout)
        }
    }
}
