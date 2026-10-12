import Combine

/// Rule-window state belongs to the application lifetime, not a preferences page.
final class RulesNavigation: ObservableObject {
    @Published var selection: String?
    @Published var showsDefaults = true
    @Published var searchText = ""
    @Published var showsAppLibrary = false

    func reveal(_ appID: String? = nil) {
        guard let appID else { return }
        showsDefaults = false
        searchText = ""
        selection = appID
    }
}
