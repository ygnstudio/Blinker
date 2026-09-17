import BlinkerCore
import SwiftUI

/// The three traffic-light status dots, shared by the rule list rows and
/// the list footer's legend: a filled dot marks a light carrying at least
/// one custom action, a hollow ring a fully default light. The trio makes
/// each rule's configuration depth scannable without opening it.
struct TrafficLightTrio: View {
    /// Per light: whether any of the five click variants carries an action.
    private let remappedLights: [TrafficButton: Bool]

    /// The status mapping as computed by the rule rows.
    init(remappedLights: [TrafficButton: Bool]) {
        self.remappedLights = remappedLights
    }

    /// The legend's fixed state: every light uniformly filled or hollow.
    init(allFilled: Bool) {
        var lights: [TrafficButton: Bool] = [:]
        for button in TrafficButton.allCases {
            lights[button] = allFilled
        }
        self.init(remappedLights: lights)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TrafficButton.allCases, id: \.self) { button in
                let color = Color(nsColor: OverlayChipDrawing.vividColor(for: button))
                let isRemapped = remappedLights[button] == true
                Circle()
                    .strokeBorder(isRemapped ? .clear : color.opacity(0.6), lineWidth: 1)
                    .background(Circle().fill(isRemapped ? color : .clear))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
