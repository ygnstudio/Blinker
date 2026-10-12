import SwiftUI

/// Draws the approved content treatment while retaining real Button semantics.
struct EclipseWorkbenchButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, quiet }
    var role: Role = .secondary
    @Environment(\.eclipsePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: role == .primary ? .medium : .regular))
            .foregroundStyle(role == .primary ? palette.actionText : palette.text)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1),
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var background: Color {
        switch role {
        case .primary: palette.action
        case .secondary: palette.hover
        case .quiet: .clear
        }
    }
}
