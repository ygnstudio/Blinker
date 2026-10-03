import SwiftUI

/// Window placement preferences and the optional saved-workspace experiment.
struct WindowManagementTab: View {
    @ObservedObject private var preferences = AppPreferences.shared
    let onSnapEnabledChange: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("开启拖拽贴靠", isOn: snapBinding)
            } header: {
                Text("拖拽贴靠（可选）")
            } footer: {
                Text("默认关闭。启用前请确认不会与系统或其他窗口管理工具的拖拽贴靠重复。")
            }
            WorkspaceSettingsSection()
        }
        .formStyle(.grouped)
    }

    private var snapBinding: Binding<Bool> {
        Binding(
            get: { preferences.isSnapEnabled },
            // The coordinator owns both persistence and applying the live snapper state.
            set: onSnapEnabledChange
        )
    }
}
