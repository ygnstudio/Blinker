import AppKit
import QuartzCore

/// Compositor-only effects: no timer, frame capture or per-frame Swift drawing.
@MainActor
final class MenuBarChargingAnimation {
    private weak var host: NSView?
    private var container: CALayer?
    private var lastKey: Key?
    private let reducedMotion: () -> Bool
    private let lowPower: () -> Bool

    init(reducedMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         lowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }) {
        self.reducedMotion = reducedMotion
        self.lowPower = lowPower
    }

    private struct Key: Equatable {
        var size: CGFloat
        var bounds: CGRect
        var percentage: Int
        var configuration: MenuBarConfiguration
        var appearance: NSAppearance.Name
    }

    static func isAllowed(snapshot: MenuBarSystemSnapshot, configuration: MenuBarConfiguration,
                          suspended: Bool, reducedMotion: Bool, lowPower: Bool) -> Bool {
        snapshot.battery?.isCharging == true && snapshot.battery?.percentage != nil
            && !suspended && !reducedMotion && !lowPower && snapshot.battery?.isLowPower != true
            && configuration.showsChargingEffect
    }

    func update(button: NSStatusBarButton, snapshot: MenuBarSystemSnapshot,
                configuration: MenuBarConfiguration, size: CGFloat, suspended: Bool) {
        update(
            host: button,
            snapshot: snapshot,
            configuration: configuration,
            size: size,
            suspended: suspended
        )
    }

    /// The settings preview uses the same compositor layers as the actual status button.
    func update(host view: NSView, snapshot: MenuBarSystemSnapshot,
                configuration: MenuBarConfiguration, size: CGFloat, suspended: Bool) {
        let configuration = configuration.normalized()
        guard Self.isAllowed(snapshot: snapshot, configuration: configuration, suspended: suspended,
                             reducedMotion: reducedMotion(), lowPower: lowPower()),
            size.isFinite, size > 0, !view.bounds.isEmpty else {
            stop()
            return
        }
        let key = Key(size: size, bounds: view.bounds, percentage: snapshot.battery?.percentage ?? 0,
                      configuration: configuration, appearance: view.effectiveAppearance.name)
        guard key != lastKey || host !== view else { return }
        stop()
        lastKey = key
        host = view
        view.wantsLayer = true
        guard let parent = view.layer else { return }
        let layer = CALayer()
        layer.name = "blinkerChargingEffects"
        layer.frame = CGRect(x: view.bounds.midX - size / 2,
                             y: view.bounds.midY - size / 2, width: size, height: size)
        layer.masksToBounds = true
        parent.addSublayer(layer)
        container = layer
        let indicator = TrioIconMapping.batteryIndicator(snapshot.battery, configuration: configuration)
        let gap: CGFloat = indicator == .bolt || indicator == .plug ? 50 : 64
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let path = TrioIconGeometry.batteryArc(from: 0, to: Double(key.percentage) / 100,
                                                   hasTopGap: indicator != .none, topGapWidth: gap)
            let glow = shape(path: path, size: size, flipped: view.isFlipped)
            glow.name = "charge"
            glow.fillColor = nil
            glow.lineWidth = 8 * configuration.stroke.scale * size / 120
            glow.strokeColor = NSColor.white.cgColor
            glow.opacity = 0.25
            layer.addSublayer(glow)
            let travel = CABasicAnimation(keyPath: "strokeEnd")
            travel.fromValue = 0
            travel.toValue = 1
            travel.duration = 2.8
            travel.repeatCount = .infinity
            travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(travel, forKey: "charge")
            if configuration.showsChargingHeartbeat, configuration.showsChargingIndicator,
               indicator == .bolt {
                addHeartbeat(to: layer, view: view, configuration: configuration, size: size)
            }
        }
    }

    private func addHeartbeat(to layer: CALayer, view: NSView,
                              configuration: MenuBarConfiguration, size: CGFloat) {
        let bolt = shape(path: TrioIconRenderer.chargingBoltPath(configuration: configuration),
                         size: size, flipped: view.isFlipped)
        bolt.name = "heartbeat"
        bolt.fillColor = (configuration.usesBatteryColors ? NSColor.systemGreen : .labelColor).cgColor
        layer.addSublayer(bolt)
        let heartbeat = CABasicAnimation(keyPath: "opacity")
        heartbeat.fromValue = 0.15
        heartbeat.toValue = 0.9
        heartbeat.duration = 1.2
        heartbeat.autoreverses = true
        heartbeat.repeatCount = .infinity
        heartbeat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bolt.add(heartbeat, forKey: "heartbeat")
    }

    private func shape(path: CGPath, size: CGFloat, flipped: Bool) -> CAShapeLayer {
        var transform = CGAffineTransform(a: size / 120, b: 0, c: 0,
                                          d: (flipped ? 1 : -1) * size / 120,
                                          tx: 0, ty: flipped ? 0 : size)
        let layer = CAShapeLayer()
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.path = path.copy(using: &transform)
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    func stop() {
        container?.sublayers?.forEach { $0.removeAllAnimations() }
        container?.removeFromSuperlayer()
        container = nil
        lastKey = nil
        host = nil
    }
}
