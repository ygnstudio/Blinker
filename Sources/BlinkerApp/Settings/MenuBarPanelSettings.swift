import SwiftUI

struct MenuBarPanelSettings: View {
    @ObservedObject var preferences: MenuBarPreferences

    var body: some View {
        Section {
            List {
                ForEach(preferences.configuration.sectionOrder, id: \.self) { section in
                    HStack(spacing: 12) {
                        Toggle(section.title, isOn: visibility(for: section))
                            .toggleStyle(EclipseToggleStyle())
                        EclipseReorderControls(
                            title: section.title,
                            canMoveUp: preferences.configuration.sectionOrder.first != section,
                            canMoveDown: preferences.configuration.sectionOrder.last != section,
                            moveUp: { moveSection(section, by: -1) },
                            moveDown: { moveSection(section, by: 1) }
                        )
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { offsets, destination in
                    preferences.update {
                        $0.sectionOrder.move(fromOffsets: offsets, toOffset: destination)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(272, max(96, CGFloat(preferences.configuration.sectionOrder.count) * 44 + 8)))
            .accessibilityLabel("面板区块顺序")
        } header: {
            Text("面板区块与顺序")
        } footer: {
            Text("开启显示后，可拖动或使用上下箭头排序。隐藏区块不影响状态图标。"
                + "隐藏音量区块也会停用面板滚轮调音量；全部隐藏后，仍可进入应用规则和设置。")
        }
        Section {
            Toggle("显示快速操作页", isOn: visibility(for: .quickActions))
        } header: {
            Text("快速操作页")
        } footer: {
            Text("快速操作独立为面板的第二页；页内项目在「自定义快速操作」设置中配置。")
        }
        Section {
            EclipsePicker("面板密度", selection: binding(\.panelDensity)) {
                ForEach(MenuBarConfiguration.PanelDensity.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
        } header: {
            Text("面板密度")
        } footer: {
            Text("紧凑密度缩小区块间距与边距，设备较多时可在一屏内查看。")
        }
    }

    private func moveSection(_ section: MenuBarConfiguration.Section, by offset: Int) {
        let order = preferences.configuration.sectionOrder
        guard let index = order.firstIndex(of: section),
              order.indices.contains(index + offset) else { return }
        preferences.update { $0.sectionOrder.swapAt(index, index + offset) }
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
