import SwiftUI

/// The battery block's detail rows: cycle count and health from the battery
/// controller, temperature and instantaneous power. Any field the hardware
/// does not publish simply leaves its row out.
extension SystemStatusPanel {
    @ViewBuilder
    func batteryDetailsRows(_ details: SystemBatteryDetails.Value) -> some View {
        if details.cycleCount != nil || details.healthPercent != nil {
            HStack(spacing: 12) {
                if let cycles = details.cycleCount {
                    Label(String(localized: "循环 \(cycles) 次"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
                if let health = details.healthPercent {
                    Label(String(localized: "健康度 \(health)%"), systemImage: "heart")
                }
            }
            .labelStyle(.titleAndIcon)
        }
        if details.temperatureCelsius != nil || details.powerWatts != nil {
            HStack(spacing: 12) {
                if let temperature = details.temperatureCelsius {
                    Label(String(format: "%.1f °C", temperature), systemImage: "thermometer.medium")
                }
                if let power = details.powerWatts {
                    let watts = String(format: "%.1f", abs(power))
                    Label(power >= 0
                        ? String(localized: "充电 \(watts) W")
                        : String(localized: "放电 \(watts) W"),
                        systemImage: "bolt.fill")
                }
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
