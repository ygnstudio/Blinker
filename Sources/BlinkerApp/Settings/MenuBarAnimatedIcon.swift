import AppKit
import Combine
import SwiftUI

struct MenuBarAnimatedIcon: NSViewRepresentable {
    let snapshot: MenuBarSystemSnapshot
    let configuration: MenuBarConfiguration
    let size: CGFloat
    let appearance: NSAppearance?

    func makeNSView(context _: Context) -> MenuBarAnimatedIconView {
        MenuBarAnimatedIconView(frame: CGRect(x: 0, y: 0, width: size, height: size))
    }

    func updateNSView(_ view: MenuBarAnimatedIconView, context _: Context) {
        view.update(snapshot: snapshot, configuration: configuration, size: size, appearance: appearance)
    }

    static func dismantleNSView(_ view: MenuBarAnimatedIconView, coordinator _: ()) {
        view.stop()
    }
}

/// A static production image with the same compositor-only charging layers as the menu bar.
@MainActor
final class MenuBarAnimatedIconView: NSImageView {
    private let charging = MenuBarChargingAnimation()
    private var snapshot = MenuBarSystemSnapshot.unknown
    private var configuration = MenuBarConfiguration()
    private var iconSize: CGFloat = 22
    private var subscriptions = Set<AnyCancellable>()
    private var visibilitySubscription: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleNone
        imageAlignment = .alignCenter
        setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshAnimation() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshAnimation() }
            .store(in: &subscriptions)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(snapshot: MenuBarSystemSnapshot, configuration: MenuBarConfiguration,
                size: CGFloat, appearance: NSAppearance?) {
        self.snapshot = snapshot
        self.configuration = configuration
        iconSize = size
        self.appearance = appearance
        image = TrioIconRenderer.image(snapshot: snapshot, size: size,
                                       appearance: appearance, configuration: configuration)
        refreshAnimation()
    }

    override func layout() {
        super.layout()
        refreshAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilitySubscription = nil
        if let window {
            visibilitySubscription = NotificationCenter.default
                .publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshAnimation() }
        }
        refreshAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAnimation()
    }

    override func viewDidHide() {
        super.viewDidHide()
        charging.stop()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshAnimation()
    }

    private func refreshAnimation() {
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        charging.update(host: self, snapshot: snapshot, configuration: configuration, size: iconSize,
                        suspended: !visible || isHiddenOrHasHiddenAncestor)
    }

    func stop() {
        visibilitySubscription = nil
        subscriptions.removeAll()
        charging.stop()
    }
}
