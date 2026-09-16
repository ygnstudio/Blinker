import BlinkerCore
import SwiftUI

// MARK: - Traffic-light glyph

/// The three traffic-light glyphs — close cross, minimize minus, fullscreen
/// triangles — drawn with the same proportions as the enlarged overlay chips,
/// so the settings UI's signal card and live preview show the real symbols.
struct TrafficLightGlyph: View {
    let button: TrafficButton

    /// The overlay chips' dark ink over the vivid fills.
    private var ink: Color {
        Color(nsColor: NSColor.black.withAlphaComponent(0.55))
    }

    var body: some View {
        switch button {
        case .close:
            CrossGlyph()
                .stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        case .minimize:
            MinusGlyph()
                .stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        case .zoom:
            ExpandGlyph()
                .fill(ink)
        }
    }
}

// MARK: - Glyph shapes

/// The close button's ✕, centered in the given rect.
private struct CrossGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let extent = rect.width * 0.35
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - extent, y: rect.midY - extent))
        path.addLine(to: CGPoint(x: rect.midX + extent, y: rect.midY + extent))
        path.move(to: CGPoint(x: rect.midX - extent, y: rect.midY + extent))
        path.addLine(to: CGPoint(x: rect.midX + extent, y: rect.midY - extent))
        return path
    }
}

/// The minimize button's −, centered in the given rect.
private struct MinusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let extent = rect.width * 0.42
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - extent, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + extent, y: rect.midY))
        return path
    }
}

/// The zoom button's two outward-pointing triangles, mirroring the overlay's
/// fullscreen symbol.
private struct ExpandGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let halfSpan = rect.width * 0.5
        let depth = rect.width * 0.38
        let halfHeight = rect.width * 0.24
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - halfSpan, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - halfSpan + depth, y: rect.midY - halfHeight))
        path.addLine(to: CGPoint(x: rect.midX - halfSpan + depth, y: rect.midY + halfHeight))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.midX + halfSpan, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + halfSpan - depth, y: rect.midY - halfHeight))
        path.addLine(to: CGPoint(x: rect.midX + halfSpan - depth, y: rect.midY + halfHeight))
        path.closeSubpath()
        return path
    }
}
