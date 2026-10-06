import SwiftUI

struct MenuBarPerformanceSettings: View {
    @ObservedObject var preferences: MenuBarPreferences

    var body: some View {
        Section {
            Toggle("CPU 使用率", isOn: binding(\.showsCPULoad))
            Toggle("内存用量", isOn: binding(\.showsMemoryUsage))
            Toggle("交换空间用量", isOn: binding(\.showsSwapUsage))
            Toggle("运行时间", isOn: binding(\.showsUptime))
        } header: {
            Text("面板性能区块")
        } footer: {
            Text("CPU 为相邻两次刷新的平均占用；内存口径近似活动监视器（应用内存 + 有线 + 压缩）。全部来自内核接口，本地读取，无需权限。")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
