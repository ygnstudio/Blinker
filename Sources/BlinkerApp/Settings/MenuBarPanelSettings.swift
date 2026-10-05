import SwiftUI

struct MenuBarPanelSettings: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var audio: SystemAudioController

    var body: some View {
        Section {
            ForEach(preferences.configuration.sectionOrder, id: \.self) { section in
                Toggle(section.title, isOn: visibility(for: section))
                    .toggleStyle(.checkbox)
            }
            .onMove { offsets, destination in
                preferences.update {
                    $0.sectionOrder.move(fromOffsets: offsets, toOffset: destination)
                }
            }
        } header: {
            Text("面板区块与顺序")
        } footer: {
            Text("勾选显示并拖动排序。隐藏区块不影响状态图标。隐藏音量区块也会停用面板滚轮调音量；全部隐藏后，仍可进入应用规则和设置。")
        }
        MenuBarOutputDeviceSettings(preferences: preferences, audio: audio)
            .disabled(!isVolumeSectionEnabled)
        Section {
            Toggle("滚动调节音量", isOn: binding(\.scrollAdjustsVolume))
                .disabled(!isVolumeSectionEnabled)
            Picker("响应范围", selection: binding(\.scrollScope)) {
                ForEach(MenuBarConfiguration.ScrollScope.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .disabled(!isVolumeSectionEnabled || !preferences.configuration.scrollAdjustsVolume)
            Picker("增大音量的方向", selection: binding(\.scrollDirection)) {
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
            Text("启用音量区块后，滚轮可在所选范围内调节当前输出设备音量。关闭滚轮操作后，仍可使用音量滑块；各项偏好会保留。"
                 + "若与 MOS、Scroll Reverser、LinearMouse 等滚动增强工具冲突，请在其设置中将 Blinker 设为不处理（白名单）。")
        }
    }

    private var isVolumeSectionEnabled: Bool {
        preferences.configuration.enabledSections.contains(.volume)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }

    private func visibility(for section: MenuBarConfiguration.Section) -> Binding<Bool> {
        Binding(get: { preferences.configuration.enabledSections.contains(section) }, set: { visible in
            preferences.update {
                if visible {
                    $0.enabledSections.insert(section)
                } else {
                    $0.enabledSections.remove(section)
                }
            }
        })
    }
}
