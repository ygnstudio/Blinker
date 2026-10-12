import SwiftUI

/// Keeps the original controls and section identities on the continuous workbench background.
struct EclipseFormStyle: FormStyle {
    @Environment(\.eclipsePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        if !section.header.isEmpty {
                            section.header
                                .font(.headline)
                                .foregroundStyle(palette.text)
                                .textCase(nil)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.bottom, 2)
                        }
                        if !section.content.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(section.content) { row in
                                    row
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .toggleStyle(EclipseToggleStyle())
                            .labeledContentStyle(EclipseLabeledContentStyle())
                            .controlSize(.regular)
                        }
                        if !section.footer.isEmpty {
                            section.footer
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Keyboard-accessible alternatives to dragging, using ordinary native buttons.
struct EclipseReorderControls: View {
    let title: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .help(Text("上移 \(title)"))
            .accessibilityLabel(Text("上移 \(title)"))
            .disabled(!canMoveUp)
            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .help(Text("下移 \(title)"))
            .accessibilityLabel(Text("下移 \(title)"))
            .disabled(!canMoveDown)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }
}
