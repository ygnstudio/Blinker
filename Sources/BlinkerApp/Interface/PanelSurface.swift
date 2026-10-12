import AppKit
import SwiftUI

/// A popover supplies its own material; standalone content uses the window surface.
struct PanelSurface: View {
    let usesWindowToolbar: Bool

    var body: some View {
        if usesWindowToolbar {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Color.clear
        }
    }
}
