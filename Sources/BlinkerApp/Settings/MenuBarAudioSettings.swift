import AppKit
import SwiftUI

struct MenuBarAudioSettings: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var audio: SystemAudioController

    var body: some View {
        Section {
            MenuBarOptionCardGroup(
                options: MenuBarConfiguration.VolumeStyle.allCases,
                selection: preferences.configuration.volumeStyle,
                title: { $0.title },
                image: volumeStyleImage,
                onSelect: { choice in preferences.update { $0.volumeStyle = choice } }
            )
            Toggle("蓝牙音频使用音量强调色", isOn: binding(\.usesBluetoothVolumeColor))
            Toggle("输入静音时显示麦克风指示", isOn: binding(\.showsMutedMicInIcon))
        } header: {
            Text("音量图形")
        } footer: {
            Text("强调色用于音量圆点或圆弧，与中央蓝牙图形分别设置。麦克风静音指示为橙色，显示期间音量图形暂时隐藏。")
        }
        Section {
            Toggle("显示声音输入", isOn: binding(\.showsAudioInput))
        } header: {
            Text("面板音量区块")
        } footer: {
            Text("在状态面板显示默认输入设备的音量与静音；设备被占用时标记“使用中”。")
        }
        MenuBarOutputDeviceSettings(preferences: preferences, audio: audio)
            .disabled(!isVolumeSectionEnabled)
        Section {
            Toggle("滚动调节音量", isOn: binding(\.scrollAdjustsVolume))
                .disabled(!isVolumeSectionEnabled)
            EclipsePicker("增大音量的方向", selection: binding(\.scrollDirection)) {
                ForEach(MenuBarConfiguration.ScrollDirection.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .disabled(!isVolumeSectionEnabled || !preferences.configuration.scrollAdjustsVolume)
            Toggle("跟随系统自然滚动", isOn: binding(\.naturalScrolling))
                .disabled(!isVolumeSectionEnabled || !preferences.configuration.scrollAdjustsVolume)
        } header: {
            Text("面板音量操作")
        } footer: {
            Text("滚轮仅在音量滑块区域调节音量，其余区域正常滚动。音量区块关闭时停用此功能。"
                + "若与 MOS、Scroll Reverser、LinearMouse 等滚动增强工具冲突，请在其设置中将 Blinker 设为不处理（白名单）。")
        }
    }

    private var isVolumeSectionEnabled: Bool {
        preferences.configuration.enabledSections.contains(.volume)
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
                List {
                    ForEach(ordered) { device in
                        HStack(spacing: 12) {
                            Text(device.name).lineLimit(2)
                            if device.id == audio.currentDeviceID {
                                Text("当前设备").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            EclipseReorderControls(
                                title: device.name,
                                canMoveUp: ordered.first?.uid != device.uid,
                                canMoveDown: ordered.last?.uid != device.uid,
                                moveUp: { moveOutput(device.uid, by: -1) },
                                moveDown: { moveOutput(device.uid, by: 1) }
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { offsets, destination in
                        var uids = ordered.map(\.uid)
                        uids.move(fromOffsets: offsets, toOffset: destination)
                        preferences.update { $0.outputDeviceOrder = uids }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(272, max(96, CGFloat(ordered.count) * 44 + 8)))
                .accessibilityLabel("输出设备顺序")
            }
            Button("恢复默认设备顺序") {
                preferences.update { $0.outputDeviceOrder = [] }
            }
            .disabled(preferences.configuration.outputDeviceOrder.isEmpty)
        } header: {
            Text("输出设备顺序")
        } footer: {
            Text("拖动或使用上下箭头调整状态面板中的设备顺序，不会切换当前输出设备。")
        }
    }

    private func moveOutput(_ uid: String, by offset: Int) {
        var uids = orderedOutputs.map(\.uid)
        guard let index = uids.firstIndex(of: uid), uids.indices.contains(index + offset) else { return }
        uids.swapAt(index, index + offset)
        preferences.update { $0.outputDeviceOrder = uids }
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
