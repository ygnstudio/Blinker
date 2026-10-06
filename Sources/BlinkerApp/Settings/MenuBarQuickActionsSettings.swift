import SwiftUI

/// Status-icon settings page for the panel quick actions block: row
/// visibility plus the Shortcut slot names. Slot editing is draft-based so
/// normalization never reshuffles the list mid-typing.
struct MenuBarQuickActionsSettings: View {
    @ObservedObject var preferences: MenuBarPreferences
    @State private var slotDrafts: [String] = ["", "", ""]

    var body: some View {
        Section {
            Toggle("麦克风静音", isOn: binding(\.showsQuickActionMicMute))
            Toggle("显示器清洁模式", isOn: binding(\.showsQuickActionDisplayCleaning))
            Toggle("键盘清洁模式", isOn: binding(\.showsQuickActionKeyboardCleaning))
        } header: {
            Text("面板显示")
        } footer: {
            Text("显示器清洁以全屏黑窗覆盖所有屏幕，无需权限。键盘清洁通过系统级事件拦截锁定键盘与媒体键，需辅助功能与输入监控权限；权限不足时会先引导授权。")
        }
        Section {
            ForEach(0 ..< 3, id: \.self) { index in
                TextField("快捷指令 \(index + 1)", text: slotBinding(index))
                    .onSubmit(commitSlots)
            }
        } header: {
            Text("快捷指令")
        } footer: {
            Text("名称需与「快捷指令」App 中的一致；留空的槽位不出现在面板。回车保存。")
        }
        .onAppear(perform: seedDrafts)
    }

    private func seedDrafts() {
        let slots = preferences.configuration.shortcutSlots
        slotDrafts = (0 ..< 3).map { index in index < slots.count ? slots[index] : "" }
    }

    private func slotBinding(_ index: Int) -> Binding<String> {
        Binding(get: { slotDrafts[index] },
                set: { slotDrafts[index] = $0 })
    }

    private func commitSlots() {
        preferences.update { $0.shortcutSlots = slotDrafts }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
