import AppKit
import SwiftUI

/// Exports the current app's file URL, so the receiving list gets the original app bundle.
struct DraggableAppIcon: View {
    private let appURL: URL?

    init(appURL: URL?) {
        let currentURL = RunningApplicationBundle.url
        self.appURL = appURL?.standardizedFileURL == currentURL ? currentURL : nil
    }

    var body: some View {
        Group {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .scaledToFit()
                    .onDrag { Self.itemProvider(for: appURL) }
                    .accessibilityLabel("Blinker 应用")
                    .accessibilityHint("可拖到系统授权列表；也可以在访达中显示，再用列表的加号添加。")
                    .accessibilityAction(named: Text("在访达中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([appURL])
                    }
                    .help("将应用拖到系统授权列表，或从访达中添加。")
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("当前未运行应用包")
                    .help("请运行已安装的 Blinker.app，再拖拽应用图标。")
            }
        }
        .frame(width: 64, height: 64)
    }

    static func itemProvider(for appURL: URL) -> NSItemProvider {
        // NSURL vends public.file-url, rather than copying the app's contents.
        let provider = NSItemProvider(object: appURL as NSURL)
        provider.suggestedName = appURL.lastPathComponent
        return provider
    }
}
