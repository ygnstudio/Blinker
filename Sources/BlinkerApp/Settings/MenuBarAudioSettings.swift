import AppKit
import SwiftUI

struct MenuBarAudioSettings: View {
    @ObservedObject var preferences: MenuBarPreferences

    var body: some View {
        Section {
            MenuBarOptionCardGroup(
                label: String(localized: "音量图形"),
                options: MenuBarConfiguration.VolumeStyle.allCases,
                selection: preferences.configuration.volumeStyle,
                title: { $0.title },
                image: volumeStyleImage,
                onSelect: { choice in preferences.update { $0.volumeStyle = choice } }
            )
            Toggle("蓝牙音频使用音量强调色", isOn: binding(\.usesBluetoothVolumeColor))
        } header: {
            Text("音量图形")
        } footer: {
            Text("强调色用于音量圆点或圆弧，与中央蓝牙图形分别设置。")
        }
        Section {
            Toggle("显示声音输入", isOn: binding(\.showsAudioInput))
        } header: {
            Text("面板音量区块")
        } footer: {
            Text("在状态面板显示默认输入设备的音量与静音；设备被占用时标记“使用中”。")
        }
    }

    private func volumeStyleImage(_ style: MenuBarConfiguration.VolumeStyle) -> NSImage {
        var value = preferences.configuration
        value.volumeStyle = style
        return TrioIconRenderer.image(snapshot: .optionCardPreview, size: 44,
                                      appearance: nil, configuration: value)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}

/// Device display preferences affect the status panel, not the status icon or active output.
struct MenuBarOutputDeviceSettings: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var audio: SystemAudioController

    var body: some View {
        let ordered = orderedOutputs
        Section("输出设备列表") {
            Toggle("始终显示全部输出设备", isOn: binding(\.alwaysShowsAllOutputDevices))
            LabeledContent("最多显示设备数") {
                HStack {
                    Text("\(preferences.configuration.outputDeviceLimit)")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Stepper("最多显示设备数", value: binding(\.outputDeviceLimit), in: 1 ... 20)
                        .labelsHidden()
                }
            }
            .disabled(preferences.configuration.alwaysShowsAllOutputDevices)
        }
        Section {
            if let error = audio.errorMessage {
                Text(error).foregroundStyle(.secondary)
                Button("重试读取输出设备") { audio.refresh() }
                    .disabled(audio.isBusy)
            }
            if audio.outputs.isEmpty {
                if audio.isBusy {
                    OperationProgress(message: String(localized: "正在读取输出设备…"))
                } else if audio.errorMessage == nil {
                    Text("暂无可用的输出设备").foregroundStyle(.secondary)
                }
            } else {
                ForEach(ordered) { device in
                    HStack {
                        Text(device.name).lineLimit(2)
                        if device.id == audio.currentDeviceID {
                            Text("当前设备").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .onMove { offsets, destination in
                    var uids = ordered.map(\.uid)
                    uids.move(fromOffsets: offsets, toOffset: destination)
                    preferences.update { $0.outputDeviceOrder = uids }
                }
            }
            Button("恢复默认设备顺序") {
                preferences.update { $0.outputDeviceOrder = [] }
            }
            .disabled(preferences.configuration.outputDeviceOrder.isEmpty)
        } header: {
            Text("输出设备顺序")
        } footer: {
            Text("拖动调整状态面板中的设备顺序，不会切换当前输出设备。")
        }
    }

    private var orderedOutputs: [SystemAudioOutput] {
        let order = preferences.configuration.outputDeviceOrder
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return audio.outputs.enumerated().sorted { lhs, rhs in
            let left = positions[lhs.element.uid] ?? Int.max
            let right = positions[rhs.element.uid] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
