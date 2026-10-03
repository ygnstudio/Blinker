import AppKit
import SwiftUI

/// Product identity and support; setup instructions live in onboarding and the guide.
struct AboutView: View {
    let onOpenPermissions: () -> Void
    @State private var showingLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identity
                Divider()
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    projectLinks
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("规则与窗口内容在本机处理，不上传数据，不收集使用统计。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("隐私与权限…", action: onOpenPermissions)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("GNU GPLv3")
                        Spacer()
                        Button("查看许可证") { showingLicense = true }
                    }
                    Text("允许商业使用和收费分发，分发时须遵守 GPLv3 的源码与许可要求。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "© 2026 ygnstudio · GPL-3.0-only")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
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
    }

    @ViewBuilder
    private var projectLinks: some View {
        projectLink("源代码", url: ProjectLinks.source, symbol: "chevron.left.forwardslash.chevron.right")
        projectLink("使用指南", url: ProjectLinks.guide, symbol: "book")
        projectLink("反馈问题", url: ProjectLinks.feedback, symbol: "bubble.left")
        projectLink("小红书主页", url: ProjectLinks.social, symbol: "person.crop.circle")
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return String(localized: "版本 \(version)（构建 \(build)）")
    }

    @ViewBuilder
    private func projectLink(_ title: LocalizedStringKey, url: URL?, symbol: String) -> some View {
        if let url {
            Link(destination: url) { Label(title, systemImage: symbol) }
        }
    }
}
