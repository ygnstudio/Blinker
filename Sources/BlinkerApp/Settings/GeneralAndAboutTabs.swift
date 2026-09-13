import BlinkerCore
import SwiftUI

// MARK: - General tab

// MARK: - General tab

/// Language and appearance preferences; both default to following the system.
struct GeneralTab: View {
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        Form {
            Section {
                Picker(tr("语言", "Language"), selection: $preferences.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.menuLabel).tag(language)
                    }
                }
                Picker(tr("外观", "Appearance"), selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.menuLabel).tag(appearance)
                    }
                }
            } header: {
                Text(tr("语言与外观", "Language & Appearance"))
            } footer: {
                Text(tr(
                    "「跟随系统」读取系统语言与深浅色设置；更改立即生效。",
                    "Follow System reads the system language and appearance; changes apply immediately."
                ))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About tab

/// The about tab: app identity, version and project links.
struct AboutTab: View {
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            identityHeader
                .padding(.vertical, 20)
            Form {
                Section {
                    featureRow(
                        color: .red,
                        text: tr("红灯重定义：退出应用或关闭窗口", "Red: quit the app or close the window")
                    )
                    featureRow(
                        color: .green,
                        text: tr("绿灯重定义：最大化、全屏或左右半屏", "Green: maximize, fullscreen, or tiling")
                    )
                    featureRow(
                        icon: "hand.point.up.left",
                        text: tr(
                            "悬停放大与纯热区点击，防误触进度环",
                            "Hover overlay & hotspot clicks with a dwell ring"
                        )
                    )
                    featureRow(
                        icon: "sparkles",
                        text: tr("macOS 26+ 原生液态玻璃质感", "Native Liquid Glass on macOS 26+")
                    )
                } header: {
                    Text(tr("功能", "Features"))
                }

                Section {
                    linkRow(
                        title: "ygnstudio/Blinker · GitHub",
                        url: URL(string: "https://github.com/ygnstudio/Blinker")!
                    )
                    linkRow(
                        title: tr("小红书主页", "Xiaohongshu Profile"),
                        url: URL(
                            string: "https://www.xiaohongshu.com/user/profile/66a7e7ae000000001d023641"
                        )!
                    )
                } header: {
                    Text(tr("链接", "Links"))
                } footer: {
                    Text(tr(
                        "使用需在系统设置中授予辅助功能权限；红绿灯行为由你为每个应用单独定义。",
                        "Grant Accessibility permission to get started;"
                            + " each app's buttons are remapped individually."
                    ))
                }
            }
            .formStyle(.grouped)
        }
    }

    private var identityHeader: some View {
        VStack(spacing: 4) {
            Image(systemName: "circle.circle")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Blinker")
                .font(.title2.bold())
            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return tr("版本", "Version") + " \(version ?? "dev") · MIT"
    }

    private func featureRow(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.callout)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 10)
            Text(text)
                .font(.callout)
        }
    }

    private func linkRow(title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
