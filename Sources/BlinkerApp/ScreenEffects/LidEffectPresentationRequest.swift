import Foundation

/// A valid gesture owns a presentation until its final frame, even if capture starts late.
struct LidEffectPresentationRequest {
    private(set) var isRequested = false
    private(set) var isFinishing = false
    private(set) var hasPresented = false
    private(set) var progress = 0.0
    private(set) var initialProgress = 0.0
    private var peakProgress = 0.0

    mutating func update(progress: Double, openingStartProgress: Double?) -> Bool {
        guard progress.isFinite, progress >= 0 else { return false }
        let seed = openingStartProgress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
        guard progress > 0 || seed > 0 else { return false }
        isRequested = true
        self.progress = min(1, progress)
        isFinishing = progress == 0
        peakProgress = max(peakProgress, self.progress, seed)
        if !hasPresented {
            initialProgress = max(initialProgress, seed)
        }
        return true
    }

    /// Returning true means the renderer needs one new finishing request.
    mutating func finish() -> Bool {
        guard isRequested, !isFinishing else { return false }
        progress = 0
        isFinishing = true
        if !hasPresented {
            initialProgress = max(initialProgress, peakProgress)
        }
        return true
    }

    mutating func didPresent() {
        hasPresented = true
        initialProgress = 0
    }

    mutating func clear() {
        self = .init()
    }
}
