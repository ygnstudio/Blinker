import SwiftUI

/// Arranges the label without replacing the native switch, its binding or keyboard behavior.
struct EclipseToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 20) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Toggle(configuration)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
        }
        .frame(minHeight: 28)
    }
}

/// Values and native controls share the same trailing edge as switches.
struct EclipseLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 20) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            configuration.content
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 28)
    }
}

/// A native menu picker with an explicit label/value row, independent of Form column inference.
struct EclipsePicker<Selection: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    private let content: Content

    init(_ title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title
        _selection = selection
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            Picker(title, selection: $selection) { content }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 260, alignment: .trailing)
        } label: {
            Text(title)
        }
        .labeledContentStyle(EclipseLabeledContentStyle())
    }
}
