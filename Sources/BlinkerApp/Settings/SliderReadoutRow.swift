import SwiftUI

/// Shared numeric setting with a stable readout and an independently adjustable accessibility element.
struct SliderReadoutRow: View {
    let label: String
    let readout: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 200)
                    .accessibilityLabel(label)
                    .accessibilityValue(readout)
                Text(readout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        // Keep adjacent Form rows separate instead of merging their labels into static text.
        .accessibilityElement(children: .contain)
    }
}
