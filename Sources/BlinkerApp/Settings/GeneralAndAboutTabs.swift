import AppKit
import BlinkerCore
import ServiceManagement
import SwiftUI

// MARK: - General tab

/// Language, appearance and interception preferences; both lookups default
/// to following the system.
struct GeneralTab: View {
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var launchAtLogin = false
    @State private var launchAtLoginError = false
    /// Set once the onAppear load has run, so the initial state assignment
    /// does not re-register an already-registered login item via onChange.
    @State private var didLoadLaunchAtLogin = false

    var body: some View {
        Form {
            interceptionSection

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
                SectionHeader(
                    title: tr("语言与外观", "Language & Appearance"),
                    info: tr(
                        "「跟随系统」读取系统语言与深浅色设置；更改立即生效。"
                            + "外观仅作用于设置窗口；悬停放大的液态玻璃始终跟随系统深浅色。",
                        "Follow System reads the system language and appearance; changes apply"
                            + " immediately. The appearance setting styles the settings window only —"
                            + " the hover overlay's glass always follows the system appearance."
                    )
                )
            }

            Section {
                Toggle(
                    tr("登录时启动 Blinker", "Launch Blinker at Login"),
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    // Skip the initial load assignment (see onAppear below);
                    // only user flips reach the system registration.
                    guard didLoadLaunchAtLogin else { return }
                    updateLaunchAtLogin(newValue)
                }
            } header: {
                SectionHeader(
                    title: tr("启动", "Startup"),
                    info: tr(
                        "开启后 Blinker 随系统登录自动启动，常驻菜单栏。",
                        "Blinker starts automatically when you log in and lives in the menu bar."
                    )
                )
            } footer: {
                if launchAtLoginError {
                    Text(tr(
                        "注册登录自启失败，请重试或检查系统设置 → 通用 → 登录项。",
                        "Could not update the login item; retry or check System Settings"
                            + " → General → Login Items."
                    ))
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Only the user-facing assignment; the onChange guard above
            // keeps this from re-registering the login item on every visit.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            didLoadLaunchAtLogin = true
        }
    }

    /// Pause/resume for click interception — moved out of the menu bar menu
    /// so the icon click can open settings directly.
    private var interceptionSection: some View {
        Section {
            Toggle(tr("启用红绿灯拦截", "Enable Interception"), isOn: interceptionBinding)
        } header: {
            Text(tr("拦截", "Interception"))
        } footer: {
            Text(
                appDelegate.status.localizedLabel
                    + tr(
                        "。暂停后红绿灯点击与悬停放大恢复系统默认行为。",
                        ". While paused, traffic-light clicks and the hover overlay use system defaults."
                    )
            )
        }
    }

    private var interceptionBinding: Binding<Bool> {
        Binding(
            get: { appDelegate.isIntercepting },
            set: { newValue in
                if appDelegate.isIntercepting != newValue {
                    appDelegate.toggleInterception()
                }
            }
        )
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = false
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = true
        }
    }
}

// MARK: - About tab

/// The about tab: app identity, version line and plain feature / link
/// rows, matching the minimal first-party macOS 26 about pages — no
/// marketing cards, gradient tiles or capsule badges.
struct AboutTab: View {
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                identityHeader
                featureGrid
                linksColumn
                Text(tr(
                    "使用需在系统设置中授予辅助功能权限；红绿灯行为由你为每个应用单独定义。",
                    "Grant Accessibility permission to get started;"
                        + " each app's buttons are remapped individually."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var identityHeader: some View {
        VStack(spacing: 8) {
            Group {
                if let icon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "circle.circle")
                        .resizable()
                        .foregroundStyle(.tint)
                        .padding(8)
                }
            }
            .frame(width: 72, height: 72)

            Text("Blinker")
                .font(.title.bold())
            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionLine: String {
        // Local dev builds carry a git-describe version ("v0.2.2-42-g3a3486c");
        // the line shows just the release number plus the build number, like
        // first-party about pages do.
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let release = raw.flatMap { $0.split(separator: "-").first }.map(String.init) ?? raw
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let buildSuffix = build.map { " (\($0))" } ?? ""
        return tr("版本", "Version") + " \(release ?? "dev")\(buildSuffix) · MIT"
    }

    // MARK: Feature rows

    /// A two-column grid of plain icon + text rows — no card backgrounds,
    /// no gradient tiles; the tinted SF Symbol carries the color.
    private var featureGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
            alignment: .leading,
            spacing: 12
        ) {
            featureRow(
                icon: "xmark.circle.fill",
                color: .red,
                text: tr("红灯重定义：退出应用或关闭窗口", "Red: quit the app or close the window")
            )
            featureRow(
                icon: "arrow.up.left.and.arrow.down.right",
                color: .green,
                text: tr("绿灯重定义：最大化、全屏或贴靠", "Green: maximize, fullscreen, or tiling")
            )
            featureRow(
                icon: "hand.point.up.left.fill",
                color: .purple,
                text: tr("悬停放大与纯热区，防误触进度环", "Hover overlay & hotspot with a dwell ring")
            )
            featureRow(
                icon: "sparkles",
                color: .blue,
                text: tr("macOS 26+ 原生液态玻璃质感", "Native Liquid Glass on macOS 26+")
            )
        }
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Link rows

    // Constant literal URLs: the force-unwrap is reviewed with every change
    // to the string, which SwiftLint cannot know — hence the explicit
    // exemption here rather than at each call site.
    // swiftlint:disable:next force_unwrapping
    private static let githubURL = URL(string: "https://github.com/ygnstudio/Blinker")!

    // The Xiaohongshu profile link (kept multi-line: the raw URL is long,
    // and splitting it would break the literal).
    // swiftlint:disable:next force_unwrapping
    private static let xiaohongshuURL = URL(
        string: "https://www.xiaohongshu.com/user/profile/66a7e7ae000000001d023641"
    )!

    private var linksColumn: some View {
        VStack(spacing: 8) {
            linkRow(
                title: "ygnstudio/Blinker · GitHub",
                systemImage: "link",
                url: Self.githubURL
            )
            linkRow(
                title: tr("小红书主页", "Xiaohongshu Profile"),
                systemImage: "book.closed",
                url: Self.xiaohongshuURL
            )
        }
    }

    /// A plain system-styled link row: tinted symbol, tinted title and the
    /// standard external-link arrow — no custom card chrome.
    private func linkRow(title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.tint)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
