import AppKit
import Foundation

/// Main-thread dwell tracking for the overlay chips: owns the hovered
/// panel, the 30 fps dwell timer and the progress fill. A dwell gate
/// (progress ring) protects against accidental clicks.
final class OverlayDwellController {
    private(set) var hoveredPanel: (any OverlayDwellPanel)?
    private var timer: Timer?
    private var startedAt: Date?
    private var activeMilliseconds = 0

    /// Applies a hover transition: resets the previous panel's dwell and
    /// starts (or skips, when dwell is 0 ms) dwell on the newly hovered one.
    func applyHoverTransition(
        dwellPanels: [any OverlayDwellPanel],
        hoveredIndex: Int?,
        dwellMilliseconds: Int
    ) {
        guard let index = hoveredIndex, dwellPanels.indices.contains(index) else {
            stop()
            return
        }
        let panel = dwellPanels[index]
        guard panel !== hoveredPanel else { return }
        hoveredPanel?.resetDwell()
        hoveredPanel = panel
        activeMilliseconds = dwellMilliseconds
        startedAt = Date()
        if dwellMilliseconds <= 0 {
            panel.setDwellProgress(1)
            stopTimer()
        } else {
            startTimer()
        }
    }

    func stop() {
        hoveredPanel?.resetDwell()
        hoveredPanel = nil
        startedAt = nil
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let panel = hoveredPanel, let start = startedAt else { return }
        let elapsedMilliseconds = Date().timeIntervalSince(start) * 1000
        let progress = HoverOverlayGeometry.dwellProgress(
            elapsedMilliseconds: elapsedMilliseconds,
            dwellMilliseconds: activeMilliseconds
        )
        panel.setDwellProgress(progress)
        if progress >= 1 {
            stopTimer()
        }
    }
}
