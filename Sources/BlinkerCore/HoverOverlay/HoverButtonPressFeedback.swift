import AppKit

/// Moves only the contents of one chip. AppKit keeps the original button
/// bounds for tracking, and the surrounding glass and tray never resize.
final class HoverButtonPressFeedback: NSView {
    private let face: NSView
    private var isPressed = false
    private var isHovered = false
    private var reducesMotion = false
    private static let animationKey = "hoverButtonFeedback"
    // Hover stays inside the glass rim. Press acknowledges input immediately;
    // hover and release ease to their new size without a spring overshoot.
    private static let hoverScale: CGFloat = 1.10
    private static let pressedScale: CGFloat = 0.96
    private static let hoverDuration: TimeInterval = 0.14
    private static let releaseDuration: TimeInterval = 0.12

    init(frame: NSRect, face: NSView) {
        self.face = face
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        addSubview(face)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setHovered(_ hovered: Bool, reduceMotion: Bool, animated: Bool) {
        guard hovered != isHovered || reduceMotion != reducesMotion else { return }
        isHovered = hovered
        reducesMotion = reduceMotion
        updateFeedback(duration: animated ? Self.hoverDuration : 0)
    }

    func setPressed(_ pressed: Bool, reduceMotion: Bool, animated: Bool) {
        guard pressed != isPressed || reduceMotion != reducesMotion else { return }
        isPressed = pressed
        reducesMotion = reduceMotion
        updateFeedback(duration: !pressed && animated ? Self.releaseDuration : 0)
    }

    private func updateFeedback(duration: TimeInterval) {
        guard let layer else { return }
        let previous = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        // Leave at least half a point of native glass around the colored face,
        // including unusually large persisted sizes and constrained layouts.
        let fittingScale = min((bounds.width - 1) / max(face.bounds.width, 1),
                               (bounds.height - 1) / max(face.bounds.height, 1))
        let hoveredScale = isHovered ? max(1, min(Self.hoverScale, fittingScale)) : 1
        let scale = reducesMotion ? 1 : hoveredScale * (isPressed ? Self.pressedScale : 1)
        var transform = CATransform3DMakeScale(scale, scale, 1)
        // NSView's backing layer anchors at its origin, unlike a plain CALayer.
        transform.m41 = bounds.midX * (1 - scale)
        transform.m42 = bounds.midY * (1 - scale)
        layer.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = transform
        // Still outlines preserve both signals with Reduce Motion; never
        // dim or recolor the opaque semantic face.
        face.layer?.borderWidth = isPressed ? 1.5 : (isHovered && reducesMotion ? 1 : 0)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            face.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.35).cgColor
        }
        CATransaction.commit()

        guard duration > 0, !reducesMotion,
              !CATransform3DEqualToTransform(previous, transform) else { return }
        let transition = CABasicAnimation(keyPath: "sublayerTransform")
        transition.fromValue = NSValue(caTransform3D: previous)
        transition.toValue = NSValue(caTransform3D: transform)
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(transition, forKey: Self.animationKey)
    }
}
