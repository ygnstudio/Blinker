import AppKit
import Combine
import SwiftUI

/// Owns the settings NSWindow: lazy creation, fronting, and keeping the
/// window chrome in sync with the General tab's appearance preference.
final class SettingsWindowController {
    private var window: NSWindow?
    private var preferencesCancellable: AnyCancellable?
    /// Builds the settings content controller (an `NSHostingController`)
    /// on first open; a closure so this controller does not depend on every
    /// store behind the settings UI. Returns `NSViewController` because the
    /// view's environment-modifier chain has no nameable concrete type.
    private let makeContentController: () -> NSViewController

    /// - Parameter makeContentController: Invoked once, when the window is
    ///   first created. Capture dependencies weakly where a cycle is possible.
    init(makeContentController: @escaping () -> NSViewController) {
        self.makeContentController = makeContentController
    }

    /// Shows the settings window, creating it on first open. A plain NSWindow
    /// hosting the SwiftUI settings screen — deliberately not the SwiftUI
    /// `Settings` scene, whose private `showSettingsWindow:` selector is
    /// unreliable to invoke from AppKit in an accessory app.
    func show() {
        bringToFront()
        if window == nil {
            let window = NSWindow(contentViewController: makeContentController())
            // System Settings–style chrome: the content fills the window and
            // the traffic-light buttons float on the sidebar's own material.
            // The pane name lives inside the detail column, so the window
            // title stays hidden. The window keeps its standard opaque
            // background — on macOS 26+ the sidebar's Liquid Glass and the
            // toolbar materials are provided by the system automatically.
            window.title = "Blinker"
            window.titleVisibility = .hidden
            // Pre-26: draw no titlebar background so the sidebar material
            // runs under the traffic lights. 26+: leave it unset so the
            // system paints its Liquid Glass titlebar/toolbar material.
            if #unavailable(macOS 26.0) {
                window.titlebarAppearsTransparent = true
            }
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert(.miniaturizable)
            // Width floor for the rules tab's three columns. On-paper math
            // (sidebar 180–230 + list 224 with glass inset + inspector
            // ~460 for the matrix and grouped-form card insets) lands near
            // 870, but the grouped Form's real system insets run wider and
            // clipped the green-light column at both 880 and 920 — verified
            // on-screen twice. 980 gives the inspector ~530 at default
            // column widths, with headroom even at sidebar/list maxima.
            window.setContentSize(NSSize(width: 980, height: 500))
            window.contentMinSize = NSSize(width: 980, height: 460)
            window.center()
            window.isReleasedWhenClosed = false
            // Normal level: `bringToFront()` handles the initial fronting;
            // a floating window would permanently cover other apps' windows.
            window.appearance = AppPreferences.shared.nsAppearance
            self.window = window
            observeWindowVisibility()
            observePreferenceChanges()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Activates the app so newly opened windows (settings) appear on top.
    /// Menu bar apps run with the `.accessory` policy and are not activated
    /// automatically when they open a window.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Safety net: whenever the settings window becomes key, pull the app
    /// to the front again. Covers paths that bypass `bringToFront()`.
    /// Scoped to the settings window only — activating on *any* key window
    /// would aggressively steal focus from other apps.
    private func observeWindowVisibility() {
        guard let window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.bringToFront()
        }
    }

    /// Keeps the settings window chrome in sync with the General tab:
    /// `NSAppearance` lives on the AppKit side, so SwiftUI's
    /// `preferredColorScheme` alone leaves the titlebar one step behind the
    /// content. Language needs no window-side work — the String Catalog
    /// follows the system, and the SwiftUI tree re-renders itself.
    private func observePreferenceChanges() {
        preferencesCancellable = AppPreferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the new value lands; reading
                // the preference on the next turn picks up the fresh value.
                DispatchQueue.main.async {
                    self?.window?.appearance = AppPreferences.shared.nsAppearance
                }
            }
    }
}
