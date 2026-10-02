import AppKit
import Combine

/// Shared lifecycle for the settings, rules and per-application editor windows.
final class AppWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var appearanceSubscription: AnyCancellable?
    private let makeContentController: () -> NSViewController
    private let title: String
    private let autosaveName: String
    private let contentSize: NSSize
    private let minimumSize: NSSize
    var onClose: (() -> Void)?

    init(
        title: String = "Blinker",
        autosaveName: String = "BlinkerSettings",
        contentSize: NSSize = NSSize(width: 860, height: 640),
        minimumSize: NSSize = NSSize(width: 760, height: 480),
        makeContentController: @escaping () -> NSViewController
    ) {
        self.title = title
        self.autosaveName = autosaveName
        self.contentSize = contentSize
        self.minimumSize = minimumSize
        self.makeContentController = makeContentController
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: makeContentController())
            window.title = title
            window.titleVisibility = .visible
            if #unavailable(macOS 26.0) {
                window.titlebarAppearsTransparent = true
            }
            window.styleMask.formUnion([.fullSizeContentView, .miniaturizable])
            window.toolbarStyle = .unified
            window.setContentSize(contentSize)
            window.contentMinSize = minimumSize
            window.center()
            window.setFrameAutosaveName(autosaveName)
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            appearanceSubscription = AppPreferences.shared.$appearance
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak window] appearance in window?.appearance = appearance.nsAppearance }
        }
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        onClose?()
    }
}
