import BlinkerCore
import SwiftUI

// MARK: - Flat action menu

/// A bezel-free action menu cell for the rules matrix lanes: the value text
/// plus a trailing chevron on a plain surface, opening the native menu with
/// the same titled sections and a checkmark on the current selection.
///
/// The old matrix hosted one `NSPopUpButton` per slot — fifteen bezels in a
/// grid read as a spreadsheet. The borderless `Menu` keeps every native
/// behavior (sections, checkmark, keyboard navigation, VoiceOver) while the
/// cell itself renders as flat text whose row/column semantics stay on the
/// accessibility label, exactly as before.
struct FlatActionMenu: View {
    /// Titled groups rendered as menu sections; the shared option model of
    /// every action picker surface.
    let groups: [ActionOptionGroup]
    /// Label for the `nil` (system default) option.
    var emptyLabel: String = .init(localized: "默认")
    @Binding var selection: ButtonAction?

    @State private var isHovered = false

    /// The system-default value recedes; a configured action reads primary.
    private var isSet: Bool {
        selection != nil
    }

    var body: some View {
        Menu {
            ForEach(groups.indices, id: \.self) { groupIndex in
                let group = groups[groupIndex]
                if let label = group.label {
                    Section(label) {
                        items(for: group.options)
                    }
                } else {
                    items(for: group.options)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection?.localizedLabel ?? emptyLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSet ? .primary : .tertiary)
                    .fontWeight(isSet ? .medium : .regular)
                Spacer(minLength: 2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
    }

    /// One section's options as menu buttons, with a checkmark on the
    /// current selection (the popup button's native check, rebuilt manually
    /// because `Menu` content is button-driven).
    private func items(for options: [ButtonAction?]) -> some View {
        ForEach(options.indices, id: \.self) { index in
            let option = options[index]
            Button {
                selection = option
            } label: {
                if option == selection {
                    Label(option?.localizedLabel ?? emptyLabel, systemImage: "checkmark")
                } else {
                    Text(option?.localizedLabel ?? emptyLabel)
                }
            }
        }
    }
}
