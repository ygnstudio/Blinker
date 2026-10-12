import AppKit
import Combine

/// Managed lifecycle for the main window and legitimate auxiliary windows.
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
        NSApp.activate()
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Native zoom uses a useful reading size rather than filling a large display.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let width = min(size.width, defaultFrame.width)
        let height = min(size.height, defaultFrame.height)
        return NSRect(
            x: max(defaultFrame.minX, min(window.frame.minX, defaultFrame.maxX - width)),
            y: max(defaultFrame.minY, min(window.frame.maxY, defaultFrame.maxY) - height),
            width: width, height: height
        )
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        onClose?()
    }
}
