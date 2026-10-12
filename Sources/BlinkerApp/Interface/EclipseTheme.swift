import AppKit
import SwiftUI

/// Shared by every page, including native titlebar content. The final compact
/// prototype intentionally overrides the earlier per-page color variations.
struct EclipsePalette {
    let background = EclipseTheme.adaptive(light: 0xE9E6E0, dark: 0x1D1F2B)
    let top = EclipseTheme.adaptive(light: 0xF1EBE0, dark: 0x292C3E)
    let surface = EclipseTheme.adaptive(light: 0xF3EEE6, dark: 0x262938)
    let hover = EclipseTheme.adaptive(light: 0xE4DBCD, dark: 0x333543)
    let input = EclipseTheme.adaptive(light: 0xE6DFD4, dark: 0x353743)
    let selection = EclipseTheme.adaptive(light: 0xDDC9AE, dark: 0x524336)
    let accent = EclipseTheme.adaptive(light: 0x855123, dark: 0xF0BD83)
    let text = EclipseTheme.adaptive(light: 0x302B2A, dark: 0xF1EDE7)
    let secondary = EclipseTheme.adaptive(light: 0x756B62, dark: 0xB8B4B8)
    let action = EclipseTheme.adaptive(light: 0x62432D, dark: 0xEEE3D3)
    let actionText = EclipseTheme.adaptive(light: 0xFFF8ED, dark: 0x352D2A)
    let stage = EclipseTheme.adaptive(light: 0xC9B69D, dark: 0x484656)
    let window = EclipseTheme.adaptive(light: 0xF9F2E6, dark: 0xE1D6C8)
    let windowInk = EclipseTheme.adaptive(light: 0x705E4C, dark: 0x6B5948)
    let shadow = EclipseTheme.adaptive(light: 0x60452B, dark: 0x000000).opacity(0.15)
}

/// Compatibility aliases keep auxiliary interfaces on the same color system.
enum EclipseTheme {
    static let shared = EclipsePalette()
    static var background: Color { shared.background }
    static var surface: Color { shared.surface }
    static var selection: Color { shared.selection }
    static var accent: Color { shared.accent }
    static var text: Color { shared.text }
    static var secondary: Color { shared.secondary }

    static func palette(for _: WorkbenchSection) -> EclipsePalette { shared }

    fileprivate static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

private struct EclipsePaletteKey: EnvironmentKey {
    static let defaultValue = EclipseTheme.shared
}

extension EnvironmentValues {
    var eclipsePalette: EclipsePalette {
        get { self[EclipsePaletteKey.self] }
        set { self[EclipsePaletteKey.self] = newValue }
    }
}

/// One continuous 125-degree background for the entire native window.
struct EclipseWindowBackground: View {
    let palette: EclipsePalette

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let horizontal = CGFloat(0.819152)
            let vertical = CGFloat(0.573576)
            let length = width * horizontal + height * vertical
            LinearGradient(
                stops: [.init(color: palette.top, location: 0),
                        .init(color: palette.background, location: 0.52)],
                startPoint: UnitPoint(x: 0.5 - horizontal * length / (2 * width),
                                      y: 0.5 - vertical * length / (2 * height)),
                endPoint: UnitPoint(x: 0.5 + horizontal * length / (2 * width),
                                    y: 0.5 + vertical * length / (2 * height))
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
