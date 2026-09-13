import SwiftUI

/// The about tab: app identity, version and project links.
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "circle.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text("Blinker")
                    .font(.title2.bold())
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            featureCard
                .padding(.horizontal, 24)
            Link(destination: projectURL) {
                Label("ygnstudio/Blinker · GitHub", systemImage: "link")
            }
            .font(.callout)
            Text("使用需在系统设置中授予辅助功能权限；红绿灯行为由你为每个应用单独定义。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "Version \(version ?? "dev") · MIT License"
    }

    private var projectURL: URL {
        URL(string: "https://github.com/ygnstudio/Blinker") ?? URL(filePath: "/")
    }

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            featureRow(icon: "circle.fill", color: .red, text: "红灯重定义：退出应用或关闭窗口")
            featureRow(icon: "circle.fill", color: .green, text: "绿灯重定义：最大化、全屏或左右半屏")
            featureRow(icon: "hand.point.up.left", color: .accentColor, text: "悬停放大与纯热区点击，带动作预览与防误触")
            featureRow(icon: "sparkles", color: .accentColor, text: "macOS 26+ 原生液态玻璃质感")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 12)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.callout)
        }
    }
}
