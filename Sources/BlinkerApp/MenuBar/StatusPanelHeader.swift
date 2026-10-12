import SwiftUI

/// The same navigation occupies the window toolbar or the popover's top inset.
struct StatusPanelHeader: View {
    @Binding var page: SystemStatusPanel.PanelPage
    let showsQuickActions: Bool

    var body: some View {
        if showsQuickActions {
            NavigationTabs(title: "系统状态", selection: $page,
                           values: [.status, .quickActions]) { value in
                value == .status ? "状态" : "快速操作"
            }
        } else {
            Text("状态").font(.headline)
        }
    }
}
