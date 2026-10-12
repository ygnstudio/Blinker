import BlinkerCore
import SwiftUI

struct RuleToolsMenu: View {
    @ObservedObject var store: RuleStore
    var ruleID: String?
    var files: RuleFileActions?

    var body: some View {
        Menu {
            Button("撤销规则修改") { store.undo() }
                .keyboardShortcut("z", modifiers: .command).disabled(store.isReadOnly || !store.canUndo)
            Button("重做规则修改") { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store.isReadOnly || !store.canRedo)
            if let ruleID, let target = store.rules.first(where: { $0.id == ruleID }) {
                Divider()
                Menu("从其他应用复制规则") {
                    ForEach(store.rules.filter { $0.id != ruleID }.sorted {
                        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    }) { source in
                        Button(source.displayName) { store.upsert(RuleTransfer.copying(source, to: target)) }
                    }
                }
                .disabled(store.isReadOnly || store.rules.count < 2)
                Button("恢复此应用的系统按钮行为") { store.reset(bundleIdentifier: ruleID) }
                    .disabled(store.isReadOnly)
            }
            if let files {
                Divider()
                RuleFileMenuActions(store: store, files: files)
            }
        } label: {
            Label("规则操作", systemImage: "ellipsis.circle")
        }
    }
}

private struct RuleFileMenuActions: View {
    @ObservedObject var store: RuleStore
    @ObservedObject var files: RuleFileActions

    var body: some View {
        Button("导入规则配置…") { files.importRules(into: store) }
            .disabled(store.isReadOnly || files.isBusy)
        Button("导出全部规则配置…") { files.exportRules(from: store) }
            .disabled(files.isBusy)
    }
}
