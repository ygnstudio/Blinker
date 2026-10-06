// Adapted from Status Trio by lingyired (Apache-2.0).
// Sources: Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift,
// Models/StatusMappings.swift, Models/BatteryIconOptions.swift,
// Models/VolumeIconOptions.swift, Models/RingStrokeStyle.swift.
// Commit: d1672377a172ee4cb4af53d5054610c407c0d34f
// Modified for Blinker: configurable read-only status artwork; explicit unknown
// readings; no charging animation, upstream settings store or device-control dependencies.
// See ThirdParty/StatusTrio for the license and attribution.

import AppKit
import CoreGraphics
import CoreText

enum TrioIconRenderer {
    private static let inactiveAlpha: CGFloat = 0.22
    private static let symbolCenter = CGPoint(x: TrioIconGeometry.artworkCenterX, y: 64)

    static func image(
        snapshot: MenuBarSystemSnapshot,
        size: CGFloat = 22,
        appearance: NSAppearance? = nil,
        configuration: MenuBarConfiguration = .init()
    ) -> NSImage {
        let size = size.isFinite && size > 0 && size <= 1024 ? size : 22
        let configuration = configuration.normalized()
        // AppKit resolves these colors when each menu bar draws. Do not capture
        // NSApp.appearance or rasterize the first display's light/dark palette.
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let draw = { Self.draw(snapshot: snapshot, size: size, configuration: configuration, in: context)
            }
            if let appearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.isTemplate = false // Preserve red, yellow and charging green.
        return image
    }

    private static func draw(
        snapshot: MenuBarSystemSnapshot, size: CGFloat,
        configuration: MenuBarConfiguration, in context: CGContext
    ) {
        let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor ?? CGColor(gray: 1, alpha: 1)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: size)
        let scale = size / TrioIconGeometry.canvasSize
        context.scaleBy(x: scale, y: -scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawBattery(snapshot.battery, configuration: configuration, in: context, foreground: foreground)
        drawCenter(snapshot, configuration: configuration, in: context, foreground: foreground)
        drawVolume(snapshot.volume, inputMuted: snapshot.inputMuted,
                   configuration: configuration, in: context, foreground: foreground)
    }

    private static func drawBattery(
        _ battery: MenuBarSystemSnapshot.Battery?, configuration: MenuBarConfiguration,
        in context: CGContext, foreground: CGColor
    ) {
        let indicator = TrioIconMapping.batteryIndicator(battery, configuration: configuration)
        let gapWidth: CGFloat = indicator == .bolt || indicator == .plug ? 50 : 64
        let hasGap = indicator != .none
        context.setLineWidth(8 * configuration.stroke.scale)
        context.setStrokeColor(foreground.copy(alpha: inactiveAlpha) ?? foreground)
        context.addPath(TrioIconGeometry.batteryArc(from: 0, to: 1, hasTopGap: hasGap, topGapWidth: gapWidth))
        context.strokePath()
        if let progress = TrioIconMapping.batteryProgress(battery) {
            context.setStrokeColor(batteryColor(
                TrioIconMapping.batteryColor(battery, configuration: configuration),
                foreground: foreground
            ))
            context.addPath(TrioIconGeometry.batteryArc(
                from: 0, to: progress, hasTopGap: hasGap, topGapWidth: gapWidth
            ))
            context.strokePath()
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        let fontSize = 36 * configuration.batterySymbolScale
        let boltScale = boltScale(fontSize: fontSize)
        switch indicator {
        case .bolt:
            context.setFillColor(foreground)
            context.addPath(TrioIconGeometry.batteryChargingBolt(scale: boltScale))
            context.fillPath()
        case .plug:
            let targetHeight = TrioIconGeometry.batteryChargingBolt().boundingBoxOfPath
                .height * boltScale * 1.2
            drawSymbol("powerplug.portrait.fill", pointSize: targetHeight / plugHeightPerPoint,
                       center: TrioIconGeometry.batteryTopIndicatorCenter(boltScale: boltScale),
                       in: context, foreground: foreground)
        case let .percentage(value):
            drawBatteryText(String(value), fontSize: fontSize, in: context, foreground: foreground)
        case .unknown:
            drawBatteryText("?", fontSize: fontSize, in: context, foreground: foreground)
        case .none:
            break
        }
    }

    static func chargingBoltPath(configuration: MenuBarConfiguration) -> CGPath {
        TrioIconGeometry
            .batteryChargingBolt(scale: boltScale(fontSize: 36 * configuration.batterySymbolScale))
    }

    private static func batteryColor(_ role: TrioIconMapping.BatteryColor, foreground: CGColor) -> CGColor {
        let dark = (NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 1) < 0.5
        switch role {
        case .foreground:
            return foreground
        case .critical:
            return NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(red: 1, green: 59.0 / 255, blue: 48.0 / 255, alpha: 1)
        case .charging:
            return dark
                ? CGColor(red: 31.0 / 255, green: 143.0 / 255, blue: 61.0 / 255, alpha: 1)
                : CGColor(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1)
        case .lowPower:
            return dark
                ? CGColor(red: 201.0 / 255, green: 151.0 / 255, blue: 0, alpha: 1)
                : CGColor(red: 242.0 / 255, green: 185.0 / 255, blue: 0, alpha: 1)
        }
    }

    private static func batteryFont(size: CGFloat) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    private static func drawBatteryText(
        _ text: String, fontSize: CGFloat, centered: Bool = false, in context: CGContext, foreground: CGColor
    ) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: batteryFont(size: fontSize),
            .kern: -fontSize * 0.04,
            .foregroundColor: NSColor(cgColor: foreground) ?? .labelColor,
        ]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let baseline = TrioIconGeometry.batteryValueBaseline(fontSize: fontSize)
        let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.setFillColor(foreground)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = centered
            ? CGPoint(x: TrioIconGeometry.artworkCenterX - glyphBounds.midX, y: 87 - glyphBounds.midY)
            : CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }

    private static func boltScale(fontSize: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "100",
            attributes: [.font: batteryFont(size: fontSize)]
        ))
        let glyphHeight = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
        let boltHeight = TrioIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        return glyphHeight / boltHeight * TrioIconGeometry.batteryChargingBoltCalibration
    }

    private static let plugHeightPerPoint: CGFloat = {
        let height = configuredSymbol("powerplug.portrait.fill", pointSize: 200, foreground: .labelColor)?
            .size.height
        guard let height, height.isFinite, height > 0 else { return 1.34 }
        return height / 200
    }()

    private static func bluetoothColor(foreground: CGColor) -> CGColor {
        let dark = (NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 1) < 0.5
        return dark ? CGColor(red: 0, green: 102.0 / 255, blue: 204.0 / 255, alpha: 1)
            : CGColor(red: 77.0 / 255, green: 163.0 / 255, blue: 1, alpha: 1)
    }
}

private extension TrioIconRenderer {
    static func drawCenter(
        _ snapshot: MenuBarSystemSnapshot, configuration: MenuBarConfiguration,
        in context: CGContext, foreground: CGColor
    ) {
        if configuration.showsBatteryInCenter, let percentage = snapshot.battery?.percentage {
            drawBatteryText(String(min(100, max(0, percentage))), fontSize: 38,
                            centered: true, in: context, foreground: foreground)
        } else if TrioIconMapping.replacesNetwork(snapshot, configuration: configuration) {
            let candidate = snapshot.volume?.symbolName ?? "headphones"
            let symbol = NSImage(systemSymbolName: candidate, accessibilityDescription: nil) == nil
                ? "headphones" : candidate
            drawSymbol(symbol, pointSize: 38 * configuration.bluetoothSymbolScale,
                       in: context, foreground: bluetoothColor(foreground: foreground))
        } else {
            drawNetwork(snapshot.network, configuration: configuration, in: context, foreground: foreground)
        }
    }

    static func drawNetwork(
        _ network: MenuBarSystemSnapshot.Network, configuration: MenuBarConfiguration,
        in context: CGContext, foreground: CGColor
    ) {
        let symbolSize = 38 * configuration.wifiSymbolScale
        switch network {
        case .wired, .wifi, .disconnected, .off, .unknown:
            drawBaseNetwork(network, configuration: configuration, symbolSize: symbolSize,
                            in: context, foreground: foreground)
        case .personalHotspot, .temporary, .sharing:
            drawSpecialNetwork(network, configuration: configuration, symbolSize: symbolSize,
                               in: context, foreground: foreground)
        }
    }

    private static func drawBaseNetwork(
        _ network: MenuBarSystemSnapshot.Network, configuration: MenuBarConfiguration,
        symbolSize: CGFloat, in context: CGContext, foreground: CGColor
    ) {
        switch network {
        case .wired where configuration.showsWiFiForWired:
            drawSymbol("wifi", pointSize: symbolSize, in: context, foreground: foreground)
        case .wired:
            context.setStrokeColor(foreground)
            context.setLineWidth(TrioIconGeometry.ethernetStrokeWidth)
            for path in TrioIconGeometry.ethernetChevrons() {
                context.addPath(path)
                context.strokePath()
            }
            context.setFillColor(foreground)
            for point in TrioIconGeometry.ethernetDots() {
                let radius = TrioIconGeometry.ethernetDotRadius
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                               width: radius * 2, height: radius * 2))
            }
        case let .wifi(strength):
            drawWiFiSignal(strength: strength, pointSize: symbolSize, in: context, foreground: foreground)
        case .disconnected:
            drawSymbol("wifi", value: 0, pointSize: symbolSize, in: context, foreground: foreground)
        case .off:
            drawSymbol("wifi.slash", pointSize: symbolSize, in: context, foreground: foreground)
        default:
            drawSymbol("questionmark", pointSize: 32 * configuration.wifiSymbolScale,
                       in: context, foreground: foreground)
        }
    }

    private static func drawSpecialNetwork(
        _ network: MenuBarSystemSnapshot.Network, configuration: MenuBarConfiguration,
        symbolSize: CGFloat, in context: CGContext, foreground: CGColor
    ) {
        switch network {
        case let .personalHotspot(strength):
            if configuration.showsWiFiForHotspot {
                drawWiFiSignal(strength: strength, pointSize: symbolSize,
                               in: context, foreground: foreground)
            } else {
                drawSymbol("personalhotspot", pointSize: symbolSize, in: context, foreground: foreground)
            }
        case .temporary:
            drawSymbol(configuration.showsWiFiForTemporary ? "wifi" : "dot.radiowaves.left.and.right",
                       pointSize: symbolSize, in: context, foreground: foreground)
        default: // .sharing
            drawSymbol(configuration.showsWiFiForSharing ? "wifi" : "wifi.router",
                       pointSize: symbolSize, in: context, foreground: foreground)
        }
    }

    private static func drawWiFiSignal(
        strength: Int, pointSize: CGFloat, in context: CGContext, foreground: CGColor
    ) {
        let value = TrioIconMapping.wifiValue(strength: strength)
        let color = value == 0 ? foreground.copy(alpha: inactiveAlpha) ?? foreground : foreground
        drawSymbol("wifi", value: value, pointSize: pointSize, in: context, foreground: color)
    }

    private static func drawSymbol(
        _ name: String, value: Double = 1, pointSize: CGFloat = 38,
        center: CGPoint = symbolCenter, in context: CGContext, foreground: CGColor
    ) {
        guard let symbol = configuredSymbol(name, value: value, pointSize: pointSize,
                                            foreground: NSColor(cgColor: foreground) ?? .labelColor)
        else { return }
        context.saveGState()
        defer { context.restoreGState() }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.scaleBy(x: 1, y: -1)
        symbol.draw(in: CGRect(x: center.x - symbol.size.width / 2, y: -(center.y + symbol.size.height / 2),
                               width: symbol.size.width, height: symbol.size.height))
    }

    private static func configuredSymbol(
        _ name: String, value: Double = 1, pointSize: CGFloat, foreground: NSColor
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: foreground))
        return NSImage(systemSymbolName: name, variableValue: value, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    static func drawVolume(
        _ volume: MenuBarSystemSnapshot.Volume?, inputMuted: Bool?,
        configuration: MenuBarConfiguration,
        in context: CGContext, foreground: CGColor
    ) {
        if configuration.showsMutedMicInIcon, inputMuted == true {
            drawMutedMicIndicator(in: context, foreground: foreground)
            return
        }
        let activeColor = configuration.usesBluetoothVolumeColor && volume?.isBluetooth == true
            ? bluetoothColor(foreground: foreground) : foreground
        if configuration.volumeStyle == .arc {
            drawVolumeArc(volume, scale: configuration.stroke.scale, in: context,
                          foreground: foreground, activeColor: activeColor)
            return
        }
        let level = TrioIconMapping.volumeSteps(volume)
        let radius: CGFloat = 5.5 * (1 + (configuration.stroke.scale - 1) * 0.5)
        for (index, point) in TrioIconGeometry.volumeDots().enumerated() {
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            if let level {
                let color = index < level ? activeColor : foreground.copy(alpha: inactiveAlpha) ?? foreground
                context.setFillColor(color)
                context.fillEllipse(in: rect)
            } else {
                // Unsupported output devices are not silently reported as muted.
                context.setLineWidth(2)
                context.setStrokeColor(foreground.copy(alpha: 0.5) ?? foreground)
                context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            }
        }
    }

    static func drawVolumeArc(
        _ volume: MenuBarSystemSnapshot.Volume?, scale: Double, in context: CGContext,
        foreground: CGColor, activeColor: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        let progress = TrioIconMapping.volumeProgress(volume)
        context.setLineWidth(7 * scale)
        context.setStrokeColor(foreground.copy(alpha: progress == nil ? 0.5 : inactiveAlpha) ?? foreground)
        if progress == nil {
            context.setLineDash(phase: 0, lengths: [2, 8])
        }
        context.addPath(TrioIconGeometry.volumeArc(progress: 1))
        context.strokePath()
        guard let progress, progress > 0 else { return }
        context.setStrokeColor(activeColor)
        context.addPath(TrioIconGeometry.volumeArc(progress: progress))
        context.strokePath()
    }

    /// Bottom-center mic badge that replaces the volume readout while the
    /// default input is muted. The battery arc has no bottom gap, so a
    /// clear-blend knockout cuts one — the image is alpha-composited over
    /// the menu bar, making the knockout invisible against any wallpaper.
    static func drawMutedMicIndicator(in context: CGContext, foreground: CGColor) {
        let center = CGPoint(x: TrioIconGeometry.artworkCenterX, y: 108)
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30))
        context.restoreGState()
        let orange = NSColor.systemOrange.usingColorSpace(.deviceRGB)?.cgColor ?? foreground
        drawSymbol("mic.slash.fill", pointSize: 24, center: center, in: context, foreground: orange)
    }
}

enum TrioIconMapping {
    enum BatteryColor: Equatable { case foreground, critical, lowPower, charging }
    enum BatteryIndicator: Equatable { case bolt, plug, percentage(Int), unknown, none }

    static func batteryProgress(_ battery: MenuBarSystemSnapshot.Battery?) -> Double? {
        battery?.percentage.map { Double(min(100, max(0, $0))) / 100 }
    }

    static func batteryColor(
        _ battery: MenuBarSystemSnapshot.Battery?, configuration: MenuBarConfiguration = .init()
    ) -> BatteryColor {
        guard configuration.usesBatteryColors else { return .foreground }
        guard let battery else { return .foreground }
        if let percentage = battery.percentage, Double(percentage) < configuration.batteryCriticalThreshold {
            return .critical
        }
        if battery.isLowPower {
            return .lowPower
        }
        if battery.isCharging || battery.isConnectedToPower {
            return .charging
        }
        return .foreground
    }

    static func batteryIndicator(
        _ battery: MenuBarSystemSnapshot.Battery?, configuration: MenuBarConfiguration = .init()
    ) -> BatteryIndicator {
        guard let battery else { return configuration.showsChargingIndicator ? .plug : .none }
        if configuration.showsChargingIndicator, battery.isCharging {
            return .bolt
        }
        let prefersPercentage = configuration.showsPercentageWhenConnected && configuration
            .showsBatteryPercentage
        if configuration.showsChargingIndicator, battery.isConnectedToPower, !prefersPercentage {
            return .plug
        }
        guard configuration.showsBatteryPercentage else { return .none }
        if let percentage = battery.percentage {
            return .percentage(min(100, max(0, percentage)))
        }
        return .unknown
    }

    static func volumeSteps(_ volume: MenuBarSystemSnapshot.Volume?) -> Int? {
        volumeProgress(volume).map { Int(ceil($0 * 4)) }
    }

    static func volumeProgress(_ volume: MenuBarSystemSnapshot.Volume?) -> Double? {
        guard let volume else { return nil }
        if volume.isMuted {
            return 0
        }
        guard let scalar = volume.scalar, scalar.isFinite else { return nil }
        return min(1, max(0, scalar))
    }

    static func replacesNetwork(_ snapshot: MenuBarSystemSnapshot,
                                configuration: MenuBarConfiguration) -> Bool {
        guard configuration.replacesNetworkWithBluetooth,
              snapshot.volume?.isBluetooth == true else { return false }
        guard configuration.prioritizesNetworkErrors else { return true }
        switch snapshot.network {
        case .wired, .wifi, .personalHotspot, .temporary, .sharing: return true
        case .unknown, .off, .disconnected: return false
        }
    }

    static func wifiValue(strength: Int) -> Double {
        switch min(3, max(0, strength)) {
        case 3: 1
        case 2: 0.66
        case 1: 0.33
        default: 0
        }
    }
}
