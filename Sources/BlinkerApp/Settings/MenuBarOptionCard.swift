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

/// An enum option rendered as its real production output — the choice is the preview.
struct MenuBarOptionCard: View {
    let title: String
    let isSelected: Bool
    let image: NSImage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: image)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: 88, maxHeight: 44)
                    .frame(minWidth: 64, minHeight: 56)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(isSelected ? 0.1 : 0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: isSelected ? 2 : 1
                                    )
                            }
                    }
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A labeled row of option cards replacing a text-only picker.
struct MenuBarOptionCardGroup<Option: Hashable>: View {
    let label: String
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let image: (Option) -> NSImage
    let onSelect: (Option) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
            HStack(spacing: 12) {
                ForEach(options, id: \.self) { option in
                    MenuBarOptionCard(
                        title: title(option),
                        isSelected: option == selection,
                        image: image(option)
                    ) { onSelect(option) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
