import AppKit
import BlinkerCore
import SwiftUI

final class CompatibilityWindowController: NSObject, NSWindowDelegate {
    static let shared = CompatibilityWindowController()
    private var window: NSWindow?
    private var testWindow: NSWindow?

    func show(bundleID: String? = nil) {
        let content = NSHostingController(rootView: CompatibilityView(initialBundleID: bundleID))
        let window = window ?? NSWindow(contentViewController: content)
        window.contentViewController = content
        window.title = String(localized: "兼容性检查")
        window.setContentSize(NSSize(width: 480, height: 370))
        window.isReleasedWhenClosed = false
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === testWindow {
            HoverTestWindow.register(windowID: nil)
        }
    }

    func showTestWindow() {
        let window = testWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = String(localized: "Blinker 悬浮测试")
        window.isReleasedWhenClosed = false
        window
            .contentViewController = NSHostingController(rootView: VStack(alignment: .leading, spacing: 18) {
                Text("试试左上角的红绿灯").font(.title2)
                Text("这里是真实窗口。把鼠标移到红绿灯上，检查覆盖位置、颜色、出现延迟和点击反馈。")
                Text("关闭、最小化和全屏会实际作用于这个测试窗口。可随时从设置重新打开。")
                    .foregroundStyle(.secondary)
                Text("将窗口移到屏幕边缘，或切换到其他应用，再检查悬浮按钮。")
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        window.setContentSize(NSSize(width: 600, height: 380))
        window.contentMinSize = NSSize(width: 440, height: 300)
        window.collectionBehavior.insert(.fullScreenPrimary)
        testWindow = window
        window.delegate = self
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        HoverTestWindow.register(windowID: CGWindowID(window.windowNumber))
    }
}

private struct CompatibilityView: View {
    let initialBundleID: String?
    @State private var bundleID = ""
    @State private var apps: [NSRunningApplication] = []
    @State private var report: WindowCompatibilityReport?
    @State private var checking = false

    var body: some View {
        Form {
            Picker("应用", selection: $bundleID) {
                Text("选择正在运行的应用").tag("")
                ForEach(apps, id: \.processIdentifier) { app in
                    Text(app.localizedName ?? app.bundleIdentifier ?? "").tag(app.bundleIdentifier ?? "")
                }
            }
            Button("检查当前窗口", action: inspect).disabled(checking || bundleID.isEmpty)
            if checking {
                ProgressView().controlSize(.small)
            }
            if let report {
                LabeledContent("辅助功能权限", value: report.permissionGranted ? String(localized: "已授权")
                    : String(localized: "未授权"))
                LabeledContent("窗口", value: report.windowFound ? String(localized: "已找到")
                    : String(localized: "未找到，请先打开应用窗口"))
                LabeledContent("标准红绿灯", value: "\(report.buttons.count) / 3")
                LabeledContent("移动窗口", value: support(report.canMove))
                LabeledContent("调整尺寸", value: support(report.canResize))
                Text("检查不执行任何窗口操作。结果仅针对该应用当前窗口，实际执行仍可能被应用拒绝。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apps = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.bundleIdentifier != nil
            }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            if let initialBundleID, apps.contains(where: { $0.bundleIdentifier == initialBundleID }) {
                bundleID = initialBundleID
                inspect()
            }
        }
        .onChange(of: bundleID) { _, _ in report = nil }
    }

    private func support(_ supported: Bool) -> String {
        supported ? String(localized: "支持") : String(localized: "不可用")
    }

    private func inspect() {
        checking = true
        let requestedID = bundleID
        WindowCompatibility.inspect(bundleID: requestedID) { result in
            checking = false
            if bundleID == requestedID {
                report = result
            }
        }
    }
}
