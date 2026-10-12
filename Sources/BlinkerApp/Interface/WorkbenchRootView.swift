import AppKit
import SwiftUI

/// The only workspace navigation surface. Child pages own their content, not another shell.
struct WorkbenchRootView: View {
    let rules: AnyView
    let settings: AnyView
    @ObservedObject var navigation: WorkbenchNavigation
    @ObservedObject var settingsNavigation: SettingsNavigation
    let onShowStatusPanel: () -> Void

    private var palette: EclipsePalette { EclipseTheme.palette(for: navigation.section) }

    var body: some View {
        Group {
                switch navigation.section {
                case .apps: rules
                case .windows, .devices, .system, .scenes, .settings: settings
                case .library: library
                case .tools: toolDirectory
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 13))
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .containerBackground(for: .window) { EclipseWindowBackground(palette: palette) }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { workbenchToolbar }
        .background(WorkbenchWindowChrome())
        .environment(\.eclipsePalette, palette)
        .environmentObject(navigation)
        .onChange(of: settingsNavigation.selection) { _, _ in
            navigation.showSettings(using: settingsNavigation)
        }
        .onChange(of: settingsNavigation.menuBarPage) { _, _ in
            if settingsNavigation.selection == .menuBar {
                navigation.showSettings(using: settingsNavigation)
            }
        }
    }

    @ToolbarContentBuilder
    private var workbenchToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { navigation.showApplications() } label: {
                HStack(spacing: 8) {
                    EclipseMoonIllustration(size: 21)
                    Text("Blinker").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(palette.text)
            }
            .buttonStyle(.plain)
            .help("返回应用工作区")
            .accessibilityLabel("返回应用工作区")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .principal) {
            navigationBar
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .automatic) {
            Button(action: navigation.searchApplications) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .help("搜索应用")
            .accessibilityLabel("搜索应用")
            .accessibilityIdentifier("workbench.searchApplications")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .automatic) {
            Button(action: onShowStatusPanel) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("打开状态面板")
            .accessibilityLabel("打开状态面板")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var navigationBar: some View {
        HStack(spacing: 1) {
            ForEach(WorkbenchSection.allCases) { section in
                Button {
                    navigation.show(section, settings: settingsNavigation)
                } label: {
                    Text(section.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(navigation.section == section ? palette.text : palette.secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(navigation.section == section ? palette.hover : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityValue(navigation.section == section ? "当前页面" : "")
            }
        }
        .padding(3)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 11))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主要功能")
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeading("资料", subtitle: "管理现有规则与保存的窗口布局。")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    directoryButton("规则配置", detail: "查看应用规则，导入或导出配置文件。", symbol: "doc.text") {
                        navigation.showApplications()
                    }
                    directoryButton("保存的工作区", detail: "查看、保存和管理实验窗口布局。", symbol: "rectangle.3.group") {
                        open(.workspaces)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("后续功能").font(.headline)
                    Text("剪贴板历史、截图、录屏与拖放暂存已列入平台规划，尚未接入这个版本。")
                        .font(.callout)
                        .foregroundStyle(palette.secondary)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toolDirectory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeading("所有工具", subtitle: "打开当前版本已有的功能与设置。")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    directoryButton("应用规则", detail: "红绿灯动作、应用例外与规则文件。", symbol: "app.dashed") {
                        navigation.showApplications()
                    }
                    tool("悬停按钮", "尺寸、出现延迟与扩展按钮。", "cursorarrow.rays", .hover)
                    tool("预览与切换", "窗口列表、Dock 预览与缩略图。", "macwindow.on.rectangle", .browser)
                    tool("布局与桌面", "贴靠与桌面窗口行为。", "rectangle.split.2x2", .windows)
                    tool("快捷键", "录制、清除和检查按键冲突。", "keyboard", .shortcuts)
                    tool("工作区", "保存布局，逐项恢复已有窗口。", "rectangle.3.group", .workspaces)
                    tool("组合状态图标", "电量、网络与声音的同源预览。", "menubar.rectangle", .menuBar, .icon)
                    tool("声音", "音频显示、设备列表与滚轮设置。", "speaker.wave.2", .menuBar, .audio)
                    tool("电池", "电池读数与图标细节。", "battery.75percent", .menuBar, .battery)
                    tool("网络", "网络状态、速率与地址显示。", "wifi", .menuBar, .network)
                    tool("蓝牙", "设备显示、电量与附近扫描设置。", "antenna.radiowaves.left.and.right", .menuBar, .bluetooth)
                    tool("存储", "磁盘容量与外置卷显示。", "externaldrive", .menuBar, .storage)
                    tool("性能", "CPU、内存和运行时间显示。", "chart.xyaxis.line", .menuBar, .performance)
                    tool("面板布局", "模块显示、顺序与密度。", "rectangle.grid.1x2", .menuBar, .panel)
                    tool("快速操作", "设置状态面板中的系统操作入口。", "bolt", .menuBar, .quickActions)
                    tool("Duo 屏幕特效", "传感器、参数与生成画面预览。", "macbook", .effects)
                    tool("权限与诊断", "查看授权、兼容性与操作反馈。", "hand.raised", .permissions)
                    tool("通用", "外观、登录启动与应用偏好。", "gearshape", .general)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(palette.secondary)
        }
    }

    private func tool(_ title: String, _ detail: String, _ symbol: String,
                      _ destination: SettingsDestination, _ page: MenuBarSettingsPage = .icon) -> some View {
        directoryButton(title, detail: detail, symbol: symbol) { open(destination, page) }
    }

    private func directoryButton(_ title: String, detail: String, symbol: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(palette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(palette.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .padding(14)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func open(_ destination: SettingsDestination, _ page: MenuBarSettingsPage = .icon) {
        settingsNavigation.menuBarPage = page
        settingsNavigation.selection = destination
        navigation.showSettings(using: settingsNavigation)
    }
}

/// Public window configuration; SwiftUI keeps its own window delegate and responder chain.
private struct WorkbenchWindowChrome: NSViewRepresentable {
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }
    }

    func makeNSView(context _: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context _: Context) {
        view.configureWindow()
    }
}
