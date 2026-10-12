import SwiftUI

/// System grouping supplies geometry, contrast and appearance adaptation.
struct StatusPanelGroup: ViewModifier {
    func body(content: Content) -> some View {
        GroupBox {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
