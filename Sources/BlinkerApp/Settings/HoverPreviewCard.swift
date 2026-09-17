import AppKit
import BlinkerCore
import SwiftUI

/// Live miniature of the hover overlay: a mock window whose enlarged chips,
/// glass tray and dwell ring all render from the *current* settings, so
/// every control below answers in the preview above. The chips reuse the
/// overlay's own vivid colors, glyphs and accent-ink rules — the preview is
/// the product, not an illustration of it.
struct HoverPreviewCard: View {
    let settings: HoverOverlaySettings

    /// The mock title bar's fixed geometry; the chip size itself follows the
    /// user's `enlargedSize` slider.
    private enum PreviewMetrics {
        static let windowWidth: CGFloat = 400
        static let titleBarHeight: CGFloat = 46
        static let nativeDotSize: CGFloat = 12
        static let trayPadding: CGFloat = 9
        static let chipInset: CGFloat = 18
        static let hotspotZoneWidth: CGFloat = 108
        static let hotspotZoneHeight: CGFloat = 42
    }

    private var chipSize: CGFloat {
        settings.enlargedSize
    }

    /// The dwell arc's completion (0...1); hotspot mode is always immediate.
    private var dwellProgress: Double {
        Double(settings.effectiveDwellMilliseconds) / 800
    }

    var body: some View {
        VStack(spacing: 12) {
            mockWindow
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .opacity(settings.isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.15), value: settings.isEnabled)
    }

    // MARK: - Mock window

    private var mockWindow: some View {
        VStack(spacing: 0) {
            titleBar
            // Placeholder content lines, so the mock reads as a window.
            VStack(alignment: .leading, spacing: 9) {
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(Color.primary.opacity(0.09))
                    .frame(height: 9)
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(Color.primary.opacity(0.09))
                    .frame(width: 190, height: 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(width: PreviewMetrics.windowWidth)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "悬停效果预览"))
    }

    private var titleBar: some View {
        ZStack {
            Text(String(localized: "访达"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            // The native traffic lights stay in the mock: in hotspot mode
            // they are the unchanged UI the enlarged zone surrounds; in
            // overlay mode they sit beneath the glass tray, exactly as the
            // real title bar composites under the enlarged chips.
            HStack(spacing: 8) {
                ForEach(TrafficButton.allCases, id: \.self) { button in
                    Circle()
                        .fill(Color(nsColor: OverlayChipDrawing.vividColor(for: button)))
                        .frame(
                            width: PreviewMetrics.nativeDotSize,
                            height: PreviewMetrics.nativeDotSize
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 13)
            .accessibilityHidden(true)
            overlayContent
        }
        .frame(height: PreviewMetrics.titleBarHeight)
        .background(Color.primary.opacity(0.07))
    }

    /// What hovering looks like in the active mode: the glass tray with
    /// enlarged chips (overlay), or the invisible zone outline (hotspot).
    @ViewBuilder
    private var overlayContent: some View {
        switch settings.mode {
        case .overlay:
            HStack {
                glassTray
                Spacer(minLength: 0)
            }
            .padding(.leading, PreviewMetrics.trayPadding)
        case .hotspot:
            HStack {
                hotspotZone
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
        }
    }

    // MARK: - Overlay mode

    /// The liquid-glass capsule tray with the three enlarged traffic chips
    /// plus one chip per configured extra action — the miniature of what
    /// `HoverOverlayTrayPanel` draws over the real title bar.
    private var glassTray: some View {
        HStack(spacing: chipSize * 0.32 + 3) {
            trafficChip(.close, showsDwellRing: true)
            trafficChip(.minimize)
            trafficChip(.zoom)
            ForEach(Array(settings.enabledExtraActions.enumerated()), id: \.offset) { _, action in
                extraChip(action)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: chipSize + PreviewMetrics.chipInset)
        .background(PreviewGlassCapsule())
    }

    /// One enlarged traffic chip: the vivid opaque circle with its glow and
    /// glyph, optionally wrapped by the dwell progress ring.
    private func trafficChip(_ button: TrafficButton, showsDwellRing: Bool = false) -> some View {
        let color = Color(nsColor: OverlayChipDrawing.vividColor(for: button))
        let size = chipSize
        return ZStack {
            if showsDwellRing, dwellProgress > 0 {
                Circle()
                    .trim(from: 0, to: dwellProgress)
                    .stroke(
                        Color(nsColor: .controlAccentColor),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(color)
                .shadow(color: color.opacity(0.4), radius: 5)
            TrafficLightGlyph(button: button)
                .frame(width: size * 0.38, height: size * 0.38)
        }
        .frame(width: size + 12, height: size + 12)
    }

    /// One extra-action chip: the accent-filled circle with the action's SF
    /// Symbol, ink chosen by the overlay's luminance rule.
    private func extraChip(_ action: ButtonAction) -> some View {
        let fill = NSColor.controlAccentColor
        let ink = Color(nsColor: OverlayChipDrawing.symbolInk(onFill: fill))
        let color = Color(nsColor: fill)
        return ZStack {
            Circle()
                .fill(color)
                .shadow(color: color.opacity(0.4), radius: 5)
            Image(systemName: action.extraSymbolName ?? "circle")
                .font(.system(size: chipSize * 0.38, weight: .semibold))
                .foregroundStyle(ink)
        }
        .frame(width: chipSize, height: chipSize)
    }

    // MARK: - Hotspot mode

    /// The invisible enlarged click zone, drawn as a dashed outline because
    /// the real thing is, by design, not there.
    private var hotspotZone: some View {
        RoundedRectangle(cornerRadius: 9)
            .strokeBorder(
                Color(nsColor: .controlAccentColor).opacity(0.65),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            .frame(
                width: PreviewMetrics.hotspotZoneWidth,
                height: PreviewMetrics.hotspotZoneHeight
            )
            .overlay(
                Text(String(localized: "不可见热区"))
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                    )
            )
    }

    // MARK: - Caption

    /// What the preview demonstrates, restated per mode and dwell setting —
    /// the honest summary of the controls below.
    private var caption: String {
        switch settings.mode {
        case .overlay:
            let effect = String(localized: "悬停任意窗口的红绿灯即出现此效果")
            guard settings.dwellMilliseconds > 0 else {
                return effect + String(localized: " · 点击立即响应")
            }
            return effect
                + String(localized: " · 悬停 ")
                + "\(settings.dwellMilliseconds)"
                + String(localized: " ms 后可点击")
        case .hotspot:
            return String(localized: "纯热区：外观完全不变，仅在按钮周围扩大不可见点击区，点击立即响应")
        }
    }
}

// MARK: - Glass capsule backing

/// The tray's glass background as a size-following view: `NSGlassEffectView`
/// on macOS 26+, a capsule-masked `NSVisualEffectView` before — the exact
/// same two paths the real hover tray uses.
private struct PreviewGlassCapsule: NSViewRepresentable {
    func makeNSView(context _: Context) -> PreviewGlassView {
        PreviewGlassView()
    }

    func updateNSView(_: PreviewGlassView, context _: Context) {}
}

/// Rebuilds its glass subview whenever the layout size changes (the chip
/// slider drives it continuously), keeping the capsule radius at half the
/// bounds' height.
final class PreviewGlassView: NSView {
    private var effectView: NSView?
    private var lastSize = NSSize.zero

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size != lastSize, size.width > 1, size.height > 1 else { return }
        lastSize = size
        rebuild(size: size)
    }

    private func rebuild(size: NSSize) {
        effectView?.removeFromSuperview()
        let glass = GlassBackdrop.makeView(
            size: size,
            cornerRadius: size.height / 2,
            autoresizingMask: [.width, .height]
        )
        addSubview(glass)
        effectView = glass
    }
}
