import AppKit

/// Entry and exit alone animate. A refresh of an already presented browser
/// leaves the current alpha transition and keyboard response untouched.
@MainActor
final class WindowBrowserFade {
    private var state = WindowBrowserFadeState()
    private weak var currentWindow: NSWindow?
    private let reduceMotion: () -> Bool
    private static let appearanceDuration: TimeInterval = 0.12
    private static let departureDuration: TimeInterval = 0.10

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
    }

    func show(_ window: NSWindow, orderFront: () -> Void) {
        guard let request = state.show() else { return }
        let opacity = stopCurrentAnimation(for: window) ?? 0
        currentWindow = window
        let reduced = reduceMotion()
        setOpacity(reduced ? 1 : opacity, on: window)
        orderFront()
        animate(window, to: 1, duration: reduced ? 0 : Self.appearanceDuration, request: request) {}
    }

    func hide(_ window: NSWindow, animated: Bool = true, completion: @escaping () -> Void) {
        guard let request = state.hide() else {
            if state.transition == nil {
                completion()
            }
            return
        }
        let opacity = stopCurrentAnimation(for: window) ?? window.alphaValue
        currentWindow = window
        setOpacity(opacity, on: window)
        let reduced = !animated || reduceMotion()
        if !reduced {
            window.orderFrontRegardless()
        }
        animate(window, to: 0, duration: reduced ? 0 : Self.departureDuration, request: request) {
            window.orderOut(nil)
            completion()
        }
    }

    private func stopCurrentAnimation(for next: NSWindow) -> CGFloat? {
        guard let window = currentWindow else { return nil }
        let opacity = window.alphaValue
        // AppKit stops an in-flight property animation when its animator is
        // assigned within a zero-duration context. Retain its current alpha.
        setOpacity(opacity, on: window)
        if window !== next {
            window.orderOut(nil)
        }
        return opacity
    }

    private func setOpacity(_ opacity: CGFloat, on window: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().alphaValue = opacity
        }
    }

    private func animate(_ window: NSWindow, to opacity: CGFloat, duration: TimeInterval,
                         request: WindowBrowserFadeState.Transition, completion: @escaping () -> Void) {
        guard duration > 0 else {
            setOpacity(opacity, on: window)
            if state.complete(request) {
                completion()
            }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = opacity
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.state.complete(request) else { return }
                completion()
            }
        }
    }
}

struct WindowBrowserFadeState {
    struct Transition: Equatable {
        let id = UUID()
        let showing: Bool
    }

    private(set) var isPresented = false
    private(set) var transition: Transition?

    mutating func show() -> Transition? {
        guard !isPresented else { return nil }
        isPresented = true
        let request = Transition(showing: true)
        transition = request
        return request
    }

    mutating func hide() -> Transition? {
        guard isPresented else { return nil }
        isPresented = false
        let request = Transition(showing: false)
        transition = request
        return request
    }

    mutating func complete(_ request: Transition) -> Bool {
        guard transition == request else { return false }
        transition = nil
        return true
    }
}
