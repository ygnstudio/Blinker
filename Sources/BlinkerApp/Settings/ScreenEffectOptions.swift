import SwiftUI

struct ScreenEffectOptions: View {
    @ObservedObject var preferences: LidEffectPreferences
    @ObservedObject var sensor: LidAngleMonitor
    let onCalibrate: () -> Void

    var body: some View {
        calibrationSection
        Section {
            angleRow("开合触发幅度", keyPath: \.sensitivity, range: 3 ... 15)
        } header: {
            Text("开合触发")
        } footer: {
            Text("每次开盖或合盖至少移动设定幅度才触发。数值越大，越容易忽略轻微晃动。")
        }
        transitionSection
        Section {
            angleRow("后仰", keyPath: \.tilt, range: 0 ... 80)
            percentageRow("雾面", keyPath: \.frost)
            percentageRow("暗化", keyPath: \.darkness)
            percentageRow("模糊", keyPath: \.blur)
            percentageRow("边界过渡", keyPath: \.edgeSoftness)
        } header: {
            Text("Duo 画面")
        } footer: {
            Text("桌面随合盖逐渐倾斜、雾化和变暗。关闭特效时仍可调整参数并查看模拟预览。")
        }
    }

    private var calibrationSection: some View {
        Section {
            LabeledContent("开合角度") {
                if sensor.status == .reading {
                    OperationProgress(message: String(localized: "正在读取开合角度…"))
                } else if sensor.status == .available, let angle = sensor.angle {
                    Text("\(Int(angle.rounded()))°").monospacedDigit()
                } else {
                    Text(sensorStatus).foregroundStyle(.secondary)
                }
            }
            angleRow("参考角度", keyPath: \.referenceAngle, range: 20 ... 180)
            Button("校准为当前角度", action: onCalibrate)
                .disabled(sensor.status != .available || sensor.angle
                    .map { (20 ... 180).contains($0) } != true)
            angleRow("满效果跨度", keyPath: \.fullEffectSpan, range: 5 ... 90)
        } header: {
            Text("校准与强度")
        } footer: {
            Text("先把屏幕放到平时使用的角度再校准。参考角度决定效果起点，跨度越大，画面变化越缓。")
        }
    }

    private var transitionSection: some View {
        Section {
            SliderReadoutRow(label: String(localized: "动画速度"),
                             readout: "\(Int((configuration.animationSpeed * 100).rounded()))%",
                             value: binding(\.animationSpeed), range: 0.25 ... 2, step: 0.05)
            Toggle("保持特效直到重新打开", isOn: binding(\.holdsUntilReopened))
            SliderReadoutRow(label: String(localized: "清除延时"),
                             readout: configuration.holdsUntilReopened ? String(localized: "无限")
                                 : seconds(configuration.clearDelay),
                             value: binding(\.clearDelay), range: 0 ... 5, step: 0.1)
                .disabled(configuration.holdsUntilReopened)
        } header: {
            Text("动画与结束方式")
        } footer: {
            Text("停稳后按延时淡出；开启保持后，重新开盖才恢复画面。动画速度只调整过渡快慢，100% 为原速。")
        }
    }

    private var sensorStatus: String {
        switch sensor.status {
        case .idle: String(localized: "尚未读取")
        case .reading: String(localized: "正在读取开合角度…")
        case .available: String(localized: "角度不可用")
        case .unavailable: String(localized: "未找到受支持的开合角度传感器")
        case .failed: String(localized: "读取失败，请重试")
        }
    }

    private var configuration: LidEffectConfiguration {
        preferences.configuration
    }

    private func angleRow(_ label: String.LocalizationValue,
                          keyPath: WritableKeyPath<LidEffectConfiguration, Double>,
                          range: ClosedRange<Double>) -> some View {
        SliderReadoutRow(label: String(localized: label),
                         readout: "\(Int(configuration[keyPath: keyPath].rounded()))°",
                         value: binding(keyPath), range: range, step: 1)
    }

    private func percentageRow(_ label: String.LocalizationValue,
                               keyPath: WritableKeyPath<LidEffectConfiguration, Double>) -> some View {
        SliderReadoutRow(label: String(localized: label),
                         readout: "\(Int((configuration[keyPath: keyPath] * 100).rounded()))%",
                         value: binding(keyPath), range: 0 ... 1, step: 0.01)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LidEffectConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }

    private func seconds(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(formatted) 秒")
    }
}
