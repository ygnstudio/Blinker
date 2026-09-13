import SwiftUI

extension View {
    /// Applies a system Liquid Glass card on macOS 26+, falling back to a
    /// subtle quaternary background on earlier systems so the layout stays
    /// readable everywhere.
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.background.quinary, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
