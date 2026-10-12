import SwiftUI

struct RulesWindowContent: View {
    @ObservedObject var navigation: RulesNavigation
    let onInspect: (String) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ApplicationRulesView(selection: $navigation.selection,
                             showsDefaults: $navigation.showsDefaults,
                             searchText: $navigation.searchText,
                             onInspect: onInspect,
                             onOpenSettings: onOpenSettings,
                             showingAppLibrary: $navigation.showsAppLibrary)
    }
}
