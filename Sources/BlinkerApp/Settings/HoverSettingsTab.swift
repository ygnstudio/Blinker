import BlinkerCore
import SwiftUI

/// Keeps appearance, timing and extra actions together; shortcuts have one editor.
struct HoverSettingsTab: View {
    @EnvironmentObject var store: HoverOverlaySettingsStore
    let onApply: (HoverOverlaySettings) -> Void
    let onOpenShortcuts: () -> Void

    private var settings: HoverOverlaySettings {
        store.settings
    }

    var body: some View {
        Form {
            Section {
                Toggle("开启悬停放大", isOn: isEnabledBinding)
                HoverPreviewCard(settings: settings)
                sizeSlider
                    .disabled(!settings.isEnabled)
                appearanceDelaySlider
                    .disabled(!settings.isEnabled)
                scopePicker
                    .disabled(!settings.isEnabled)
                Button("打开真实测试窗口…") { CompatibilityWindowController.shared.showTestWindow() }
            } header: {
                Text("悬停显示")
            } footer: {
                Text("放大按钮直接覆盖原生红绿灯；材质与按钮跟随所选外观。")
            }

            Section {
                HoverTimingSettings(settings: settings, onApply: onApply)
                    .disabled(!settings.isEnabled)
            } header: {
                Text("点击保护")
            } footer: {
                Text("保护期间点击不会执行，进度环结束后再点。仅保护退出时，其他操作立即响应；保护时间为零时，所有操作立即响应。")
            }

            Section {
                extraSlotsGrid.disabled(!settings.isEnabled)
            } header: {
                Text("扩展按钮")
            } footer: {
                Text("选好动作的按钮会在悬停红绿灯时出现在绿灯右侧，点击即执行该动作；留空则不显示。")
            }

            Section {
                Button("配置悬停快捷键…", action: onOpenShortcuts)
            }
        }
        .formStyle(.grouped)
    }

    /// Every action except `none` — a chip that does nothing is pointless.
    static let extraOptions: [ButtonAction?] = [nil] + ButtonAction.allCases
        .filter { $0 != .none }

    private var sizeSlider: some View {
        SliderReadoutRow(
            label: String(localized: "放大尺寸"),
            readout: "\(Int(settings.enlargedSize)) pt",
            value: enlargedSizeBinding,
            range: 28 ... 48,
            step: 1
        )
    }

    private var appearanceDelaySlider: some View {
        SliderReadoutRow(
            label: String(localized: "出现延迟"),
            readout: "\(settings.appearanceDelayMilliseconds) ms",
            value: Binding(
                get: { Double(settings.appearanceDelayMilliseconds) },
                set: { value in update { $0.appearanceDelayMilliseconds = Int(value) } }
            ),
            range: 0 ... 800,
            step: 50
        )
    }

    private var scopePicker: some View {
        Picker("作用范围", selection: appliesToAllWindowsBinding) {
            Text("全部窗口").tag(true)
            Text("仅规则应用").tag(false)
        }
    }

    private var extraSlotsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 20)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(0 ..< HoverOverlaySettings.extraSlotCount, id: \.self) { index in
                LabeledContent {
                    ActionPicker(
                        options: Self.extraOptions,
                        selection: extraBinding(index),
                        emptyLabel: String(localized: "不显示")
                    )
                } label: {
                    Text("按钮 \(index + 1)")
                        .font(.callout)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in update { $0.isEnabled = newValue } }
        )
    }

    /// The slot's configured action; `nil` hides the chip.
    private func extraBinding(_ index: Int) -> Binding<ButtonAction?> {
        Binding(
            get: {
                settings.extraButtonActions.indices.contains(index)
                    ? settings.extraButtonActions[index]
                    : nil
            },
            set: { newValue in
                update { settings in
                    if settings.extraButtonActions.indices.contains(index) {
                        settings.extraButtonActions[index] = newValue
                    }
                }
            }
        )
    }

    private var enlargedSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.enlargedSize) },
            set: { newValue in update { $0.enlargedSize = CGFloat(newValue) } }
        )
    }

    private var appliesToAllWindowsBinding: Binding<Bool> {
        Binding(
            get: { settings.appliesToAllWindows },
            set: { newValue in update { $0.appliesToAllWindows = newValue } }
        )
    }

    private func update(_ mutate: (inout HoverOverlaySettings) -> Void) {
        var updated = settings
        mutate(&updated)
        onApply(updated)
    }
}
