import BlinkerCore
import SwiftUI

struct RuleToolsMenu: View {
    @ObservedObject var store: RuleStore
    var ruleID: String?
    @StateObject private var files = RuleFileActions()

    var body: some View {
        Menu {
            Button("撤销规则修改") { store.undo() }
                .keyboardShortcut("z", modifiers: .command).disabled(!store.canUndo)
            Button("重做规则修改") { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo)
            if let ruleID, let target = store.rules.first(where: { $0.id == ruleID }) {
                Divider()
                Menu("从其他应用复制规则") {
                    ForEach(store.rules.filter { $0.id != ruleID }.sorted {
                        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    }) { source in
                        Button(source.displayName) { store.upsert(RuleTransfer.copying(source, to: target)) }
                    }
                }
                .disabled(store.rules.count < 2)
                Button("恢复此应用的默认设置") { store.reset(bundleIdentifier: ruleID) }
            }
            Divider()
            Button("导入规则…") { files.importRules(into: store) }.disabled(files.isBusy)
            Button("导出全部规则…") { files.exportRules(from: store) }
                .disabled(store.rules.isEmpty || files.isBusy)
        } label: {
            Label("规则操作", systemImage: "ellipsis.circle")
        }
    }
}
