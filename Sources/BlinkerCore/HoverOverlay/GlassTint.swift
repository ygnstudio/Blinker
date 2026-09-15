import AppKit

/// Liquid Glass tint helpers shared by every glass surface: the hover tray,
/// the management HUD, the extra chips and the app's settings window.
///
/// `NSGlassEffectView` exposes `tintColor` (and SwiftUI's `GlassEffectStyle`
/// has `.tint(_:)`), which is the same knob Apple's own settings surface as
/// a "glass tint" adjustment. There is no public strength/blur control, so
/// tint is the only dial offered.
public enum GlassTint {
    /// Encodes an sRGB color as `#RRGGBB` (alpha ignored — glass tints are
    /// always opaque definitions; the material itself handles translucency).
    public static func hexString(from color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int(round(srgb.redComponent * 255)),
            Int(round(srgb.greenComponent * 255)),
            Int(round(srgb.blueComponent * 255))
        )
    }

    /// Decodes `#RRGGBB` / `RRGGBB` into an sRGB color; `nil` for anything
    /// malformed.
    public static func color(fromHex hex: String) -> NSColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6,
              let value = UInt64(digits, radix: 16)
        else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The configured glass tint, or `nil` to follow the system accent.
    public static func resolved(hex: String?) -> NSColor? {
        hex.flatMap(color(fromHex:))
    }
}
