import SwiftUI

/// One meaningful waiting cue per operation, including when motion is reduced.
struct OperationProgress: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if reduceMotion {
                    Image(systemName: "hourglass")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            Text(message)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
