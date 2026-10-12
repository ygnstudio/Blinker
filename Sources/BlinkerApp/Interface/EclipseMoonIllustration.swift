import SwiftUI

/// The approved Eclipse crescent, drawn at the small wordmark scale.
/// Decorative only; the parent supplies any accessible brand or button label.
struct EclipseMoonIllustration: View {
    var size: CGFloat = 48

    var body: some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 0.945, blue: 0.784), location: 0),
                    .init(color: Color(red: 0.918, green: 0.729, blue: 0.455), location: 0.37),
                    .init(color: Color(red: 0.612, green: 0.376, blue: 0.212), location: 0.68),
                    .init(color: Color(red: 0.286, green: 0.192, blue: 0.204), location: 1),
                ],
                center: UnitPoint(x: 0.28, y: 0.25), startRadius: 0, endRadius: size * 0.78
            ))
            .mask {
                Circle()
                    .overlay {
                        Circle()
                            .scaleEffect(0.96)
                            .offset(x: size * 0.19, y: -size * 0.22)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .rotationEffect(.degrees(-13))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
