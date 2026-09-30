import AppKit
import SwiftUI

/// Product identity and support; setup instructions live in onboarding and the guide.
struct AboutTab: View {
    @State private var showingLicense = false

    var body: some View {
        Form {
            Section {
                identity
            }
            Section("项目与联系") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { projectLinks }
                    VStack(alignment: .leading, spacing: 12) { projectLinks }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("规则与窗口内容在本机处理，不上传数据，不收集使用统计。")
                    Text("辅助功能用于识别和操作窗口。屏幕录制仅用于可选缩略图，图像只缓存在内存中。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("隐私与权限")
            } footer: {
                Text("外部链接由默认浏览器打开。")
            }
            Section {
                LabeledContent("GNU GPLv3") {
                    Button("查看许可证") { showingLicense = true }
                }
                Text("允许商业使用和收费分发，分发时须遵守 GPLv3 的源码与许可要求。")
                    .foregroundStyle(.secondary)
            } header: {
                Text("开源许可")
            } footer: {
                Text(verbatim: "© 2026 ygnstudio · GPL-3.0-only")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingLicense) { LicenseSheet() }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blinker").font(.title.bold())
                    Text("macOS 窗口工具")
                    Text(versionLine).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text("自定义红绿灯动作，放大悬停按钮，预览、切换和整理窗口。")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var projectLinks: some View {
        projectLink("源代码", path: "", symbol: "chevron.left.forwardslash.chevron.right")
        projectLink("使用说明", path: "#readme", symbol: "book")
        projectLink("反馈问题", path: "/issues", symbol: "bubble.left")
        if let url = URL(
            string: "https://www.xiaohongshu.com/user/profile/66a7e7ae000000001d023641"
        ) {
            Link(destination: url) { Label("小红书主页", systemImage: "person.crop.circle") }
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return String(localized: "版本 \(version)（构建 \(build)）")
    }

    @ViewBuilder
    private func projectLink(_ title: LocalizedStringKey, path: String, symbol: String) -> some View {
        // Fixed project destinations never include rules or window content.
        if let url = URL(string: "https://github.com/ygnstudio/Blinker" + path) {
            Link(destination: url) { Label(title, systemImage: symbol) }
        }
    }
}
