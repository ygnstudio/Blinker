import BlinkerCore
import SwiftUI

struct ApplicationRuleEditor: View {
    @ObservedObject var ruleStore: RuleStore
    let ruleID: AppRule.ID
    @AppStorage("appAppearance") private var appearance = AppAppearance.system

    var body: some View {
        Group {
            if let rule = ruleStore.rules.first(where: { $0.id == ruleID }) {
                RuleInspectorView(rule: rule, onUpdate: { ruleStore.upsert($0) })
            } else {
                ContentUnavailableView("规则已删除", systemImage: "macwindow")
            }
        }
        .preferredColorScheme(appearance.resolvedScheme)
        .toolbar {
            ToolbarItem { RuleToolsMenu(store: ruleStore, ruleID: ruleID) }
            ToolbarItem {
                Button("检查兼容性", systemImage: "checkmark.shield") {
                    CompatibilityWindowController.shared.show(bundleID: ruleID)
                }
            }
        }
    }
}
