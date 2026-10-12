import AppKit
import SwiftUI

extension MenuBarSystemSnapshot {
    /// Fixed healthy state so option cards vary only the setting under choice.
    static let optionCardPreview = MenuBarSystemSnapshot(
        battery: .init(percentage: 95, isCharging: false, isConnectedToPower: false, isLowPower: false),
        network: .wifi(strength: 3),
        volume: .init(scalar: 0.5, isMuted: false, symbolName: nil)
    )
}

/// System radio selection with a noninteractive preview of each production image.
struct MenuBarOptionCardGroup<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let image: (Option) -> NSImage
    let onSelect: (Option) -> Void

    var body: some View {
        Picker("音量图形", selection: Binding(get: { selection }, set: onSelect)) {
            ForEach(options, id: \.self) { option in
                HStack {
                    Text(title(option))
                    Image(nsImage: image(option))
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
                .tag(option)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .controlSize(.regular)
    }
}
