import SwiftUI

struct MenuBarStorageSettings: View {
    @ObservedObject var preferences: MenuBarPreferences

    var body: some View {
        Section {
            Toggle("内置磁盘可用空间", isOn: binding(\.showsInternalStorage))
            Toggle("外置卷与推出按钮", isOn: binding(\.showsExternalVolumes))
        } header: {
            Text("面板存储区块")
        } footer: {
            Text("容量口径与访达一致（十进制 GB）。推出按钮作用于每个已挂载的外置卷；推出失败会在面板行内显示原因。全部读取与推出均为本地操作，无需权限。")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
