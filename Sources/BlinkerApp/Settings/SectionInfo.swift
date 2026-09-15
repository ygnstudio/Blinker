import SwiftUI

// MARK: - Info popover

/// A small info button that reveals its text in a popover — the
/// replacement for long section footers, keeping forms dense while the
/// full explanation stays one click away.
struct SectionInfoButton: View {
    let text: String
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("详情", "Details"))
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .padding(14)
                .frame(width: 280, alignment: .leading)
        }
    }
}

// MARK: - Section header with info

/// A grouped-form section header paired with an inline info popover, so
/// each section carries its own help without a multi-line footer.
struct SectionHeader: View {
    let title: String
    let info: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            SectionInfoButton(text: info)
        }
    }
}
