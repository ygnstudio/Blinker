import AppKit
import BlinkerCore
import SwiftUI

/// The preview uses the same AppKit material and standard controls as the palette.
struct HoverPreviewCard: View {
    let settings: HoverOverlaySettings

    var body: some View {
        let size = HoverOverlayGeometry.paletteSize(
            buttonCount: 3 + settings.enabledExtraActions.count, buttonSize: settings.enlargedSize
        )
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if !settings.isEnabled {
                    HStack(spacing: 8) {
                        ForEach(TrafficButton.allCases, id: \.self) { button in
                            Circle()
                                .fill(Color(nsColor: OverlayChipDrawing.vividColor(for: button)))
                                .frame(width: 12, height: 12)
                        }
                    }
                    .padding(.leading, 18)
                }
                if settings.isEnabled {
                    PalettePreview(settings: settings)
                }
            }
            .frame(width: size.width, height: size.height)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("悬停效果预览")
    }
}

private struct PalettePreview: NSViewRepresentable {
    let settings: HoverOverlaySettings

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        view.subviews.forEach { $0.removeFromSuperview() }
        let actions: [ButtonAction] = [.closeWindow, .minimize, .fullscreen] + settings.enabledExtraActions
        let size = settings.enlargedSize
        let total = HoverOverlayGeometry.paletteSize(buttonCount: actions.count, buttonSize: size)
        let content = NSView(frame: NSRect(origin: .zero, size: total))
        content.autoresizingMask = [.width, .height]
        let colors = TrafficButton.allCases.map { OverlayChipDrawing.vividColor(for: $0) }
        for (index, action) in actions.enumerated() {
            let color = index < colors.count ? colors[index] : NSColor.controlAccentColor
            let origin = NSPoint(
                x: HoverOverlayGeometry.trayHorizontalPadding
                    + CGFloat(index) * (size + HoverOverlayGeometry.controlGap),
                y: HoverOverlayGeometry.trayVerticalPadding
            )
            let button = HoverControlAppearance.makePreviewButton(
                frame: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                action: action, color: color
            )
            let surface = HoverControlAppearance.makeSurface(for: button)
            surface.frame.origin = origin
            content.addSubview(surface)
        }
        let group = HoverControlAppearance.makeGroup(content: content, size: total)
        // SwiftUI sizes the initially empty host after this update. Keep the
        // palette at its measured size instead of adding the host's size delta.
        group.autoresizingMask = []
        view.addSubview(group)
    }
}
