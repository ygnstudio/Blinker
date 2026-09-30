import AppKit
import BlinkerCore
import SwiftUI

/// The preview uses the same AppKit material and standard controls as the palette.
struct HoverPreviewCard: View {
    let settings: HoverOverlaySettings

    var body: some View {
        HStack(spacing: 16) {
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
                        .allowsHitTesting(false)
                }
            }
            .frame(width: CGFloat(3 + settings.enabledExtraActions.count) * (settings.enlargedSize + 4) + 20,
                   height: settings.enlargedSize + 16)
            Spacer(minLength: 0)
            Text("悬停效果预览").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
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
        let total = NSSize(width: CGFloat(actions.count) * (size + 4) + 20, height: size + 16)
        let content = NSView(frame: NSRect(origin: .zero, size: total))
        content.autoresizingMask = [.width, .height]
        let colors = TrafficButton.allCases.map { OverlayChipDrawing.vividColor(for: $0) }
        for (index, action) in actions.enumerated() {
            let color = index < colors.count ? colors[index] : NSColor.controlAccentColor
            let button = HoverControlAppearance.makePreviewButton(
                frame: NSRect(x: 12 + CGFloat(index) * (size + 4), y: 8, width: size, height: size),
                action: action, color: color
            )
            let surface = HoverControlAppearance.makeSurface(for: button)
            surface.frame.origin = NSPoint(x: 12 + CGFloat(index) * (size + 4), y: 8)
            content.addSubview(surface)
        }
        view.addSubview(HoverControlAppearance.makeGroup(content: content, size: total))
    }
}
