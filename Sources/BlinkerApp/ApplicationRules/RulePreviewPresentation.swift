import BlinkerCore
import SwiftUI

/// Uses the stored rule semantics, including explicit no-op versus system behavior.
enum RulePreviewPresentation {
    static func name(_ button: TrafficButton) -> String {
        switch button {
        case .close: String(localized: "关闭按钮")
        case .minimize: String(localized: "最小化按钮")
        case .zoom: String(localized: "绿色按钮")
        }
    }

    static func resolvedAction(rule: AppRule, defaults: GlobalButtonRules = .init(),
                               button: TrafficButton, variant: ClickVariant) -> ButtonAction? {
        let engine = engine(rule: rule, defaults: defaults)
        let direct = engine.action(forBundleIdentifier: rule.id, button: button, variant: variant)
        guard direct == nil, variant == .longPressLeft else { return direct }
        return engine.action(forBundleIdentifier: rule.id, button: button, variant: .left)
    }

    static func source(rule: AppRule, defaults: GlobalButtonRules,
                       button: TrafficButton, variant: ClickVariant) -> String {
        switch rule.binding(for: button, variant: variant) {
        case .inherit:
            let action = defaults.action(for: button, variant: variant)
            let fallback = variant == .longPressLeft ? "按普通单击处理" : "系统行为"
            return "来自默认行为 · \(action?.localizedLabel ?? fallback)"
        case .system:
            return variant == .longPressLeft ? "此应用设置 · 按普通单击处理" : "此应用设置 · 系统行为"
        case let .action(action):
            return "此应用指定 · \(action.localizedLabel)"
        }
    }

    static func summary(rule: AppRule, defaults: GlobalButtonRules = .init(),
                        button: TrafficButton, variant: ClickVariant) -> String {
        guard rule.isEnabled else { return String(localized: "此应用的按钮规则已停用，配置保留。") }
        let engine = engine(rule: rule, defaults: defaults)
        if let action = engine.action(forBundleIdentifier: rule.id, button: button, variant: variant) {
            if rule.binding(for: button, variant: variant) == .inherit {
                return "沿用默认行为：\(action.localizedLabel)。"
            }
            return "\(name(button))：\(action.localizedLabel)。"
        }
        if variant == .longPressLeft,
           let action = engine.action(forBundleIdentifier: rule.id, button: button, variant: .left) {
            return String(localized: "长按未配置，按普通单击处理：\(action.localizedLabel)。")
        }
        if variant == .left || variant == .longPressLeft {
            return String(localized: "保留系统按钮行为。")
        }
        return String(localized: "未配置；原生按钮交由系统处理，悬浮按钮不执行操作。")
    }

    private static func engine(rule: AppRule, defaults: GlobalButtonRules) -> RuleEngine {
        let configuration = RuleConfiguration(rules: [rule], globalDefaults: defaults)
        return RuleEngine(configurationProvider: { configuration })
    }

    private static let layoutFrames: [ButtonAction: CGRect] = [
        .tileLeft: CGRect(x: 0.05, y: 0.15, width: 0.44, height: 0.75),
        .tileRight: CGRect(x: 0.51, y: 0.15, width: 0.44, height: 0.75),
        .tileTop: CGRect(x: 0.05, y: 0.15, width: 0.9, height: 0.35),
        .tileBottom: CGRect(x: 0.05, y: 0.55, width: 0.9, height: 0.35),
        .tileTopLeft: CGRect(x: 0.05, y: 0.15, width: 0.44, height: 0.35),
        .tileTopRight: CGRect(x: 0.51, y: 0.15, width: 0.44, height: 0.35),
        .tileBottomLeft: CGRect(x: 0.05, y: 0.55, width: 0.44, height: 0.35),
        .tileBottomRight: CGRect(x: 0.51, y: 0.55, width: 0.44, height: 0.35),
        .tileFirstThird: CGRect(x: 0.05, y: 0.15, width: 0.28, height: 0.75),
        .tileCenterThird: CGRect(x: 0.36, y: 0.15, width: 0.28, height: 0.75),
        .tileLastThird: CGRect(x: 0.67, y: 0.15, width: 0.28, height: 0.75),
        .tileFirstTwoThirds: CGRect(x: 0.05, y: 0.15, width: 0.59, height: 0.75),
        .tileLastTwoThirds: CGRect(x: 0.36, y: 0.15, width: 0.59, height: 0.75),
        .maximize: CGRect(x: 0.05, y: 0.15, width: 0.9, height: 0.75),
        .fullscreen: CGRect(x: 0.05, y: 0.15, width: 0.9, height: 0.75),
        .almostMaximize: CGRect(x: 0.12, y: 0.22, width: 0.76, height: 0.6),
    ]

    static func normalizedFrame(_ action: ButtonAction?) -> CGRect {
        action.flatMap { layoutFrames[$0] } ?? CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.55)
    }
}

/// A drawn configuration illustration, never a screenshot or a live desktop feed.
struct RuleWindowDiagram: View {
    @Environment(\.eclipsePalette) private var palette
    let action: ButtonAction?
    var appName = "Blinker"

    private var targetOpacity: Double {
        switch action {
        case .closeWindow?, .quitApp?, .hideApp?: 0.2
        default: 1
        }
    }

    private var targetFrame: CGRect {
        switch action {
        case .fullscreen?: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .minimize?: return CGRect(x: 0.43, y: 0.82, width: 0.18, height: 0.1)
        case .moveToNextDisplay?: return CGRect(x: 0.55, y: 0.27, width: 0.39, height: 0.6)
        default:
            // Reserve the prototype's menu-bar and Dock bands around the same
            // normalized action geometry used by the rest of the preview.
            let frame = RulePreviewPresentation.normalizedFrame(action)
            return CGRect(x: frame.minX, y: 0.09 + frame.minY * 0.87,
                          width: frame.width, height: frame.height * 0.87)
        }
    }

    private var legend: String {
        switch action {
        case .minimize?: String(localized: "收起至 Dock · 示意")
        case .closeWindow?: String(localized: "关闭窗口 · 示意")
        case .quitApp?: String(localized: "退出应用 · 示意")
        case .hideApp?: String(localized: "隐藏应用 · 示意")
        case .moveToNextDisplay?: String(localized: "移至另一显示器 · 示意")
        case .restorePreviousFrame?: String(localized: "还原前次位置 · 示意")
        case .none?: String(localized: "位置不变 · 示意")
        case nil: String(localized: "系统行为 · 示意")
        default: String(localized: "目标窗口 · 布局示意")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                desktop(size: geometry.size)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(palette.window).frame(width: 7, height: 7)
                Text(legend).font(.system(size: 9))
                    .foregroundStyle(palette.secondary).lineLimit(1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(appName)，\(actionLabel)。配置示意，不读取真实桌面。"))
    }

    private var actionLabel: String {
        action?.localizedLabel ?? String(localized: "系统行为")
    }

    private func desktop(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(palette.stage)
            if action != .fullscreen {
                backgroundWindow(size: size)
                menuBar.frame(width: size.width, height: 17)
                miniDock.frame(width: size.width * 0.34, height: 13)
                    .offset(x: size.width * 0.33, y: max(0, size.height - 16))
            }
            targetWindow(size: CGSize(width: size.width * targetFrame.width,
                                      height: size.height * targetFrame.height))
                .frame(width: size.width * targetFrame.width, height: size.height * targetFrame.height)
                .opacity(targetOpacity)
                .offset(x: size.width * targetFrame.minX, y: size.height * targetFrame.minY)
            if let symbol = transitionSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.window.opacity(0.85))
                    .position(x: size.width * 0.5, y: size.height * 0.58)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var menuBar: some View {
        HStack(spacing: 4) {
            Text(appName).font(.system(size: 7, weight: .medium)).lineLimit(1)
            Spacer(minLength: 2)
            Text("示意").font(.system(size: 7))
            Image(systemName: "menubar.rectangle").font(.system(size: 8))
        }
        .foregroundStyle(palette.text.opacity(0.8))
        .padding(.horizontal, 8)
        .background(palette.hover)
    }

    private func backgroundWindow(size: CGSize) -> some View {
        let appearsOnRight = targetFrame.midX > 0.65
        return RoundedRectangle(cornerRadius: 6)
            .fill(palette.surface.opacity(0.3))
            .overlay(alignment: .topLeading) {
                Capsule().fill(palette.window.opacity(0.08))
                    .frame(width: size.width * 0.15, height: 3).padding(8)
            }
            .frame(width: size.width * 0.41, height: size.height * 0.65)
            .offset(x: size.width * (appearsOnRight ? 0.05 : 0.53), y: size.height * 0.22)
    }

    private func targetWindow(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if size.height >= 28 {
                HStack(spacing: 4) {
                    trafficLights
                    Spacer(minLength: 0)
                    if size.width >= 82 {
                        Text(appName).font(.system(size: 6)).lineLimit(1)
                    }
                }
                .padding(.horizontal, 6).frame(height: 17)
            }
            if size.height >= 34 {
                documentLines(size: size)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.windowInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.window, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: palette.shadow, radius: 6, x: 0, y: 4)
    }

    private var trafficLights: some View {
        HStack(spacing: 2) {
            Circle().fill(Color(red: 0.80, green: 0.45, blue: 0.39))
            Circle().fill(Color(red: 0.79, green: 0.63, blue: 0.34))
            Circle().fill(Color(red: 0.46, green: 0.61, blue: 0.43))
        }
        .frame(width: 16, height: 4)
    }

    private func documentLines(size: CGSize) -> some View {
        let contentWidth = max(0, size.width - 20)
        return VStack(alignment: .leading, spacing: 5) {
            if size.height >= 54 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.windowInk.opacity(0.16))
                    .frame(width: contentWidth * 0.35, height: min(17, size.height * 0.2))
            }
            Capsule().fill(palette.windowInk.opacity(0.2)).frame(height: 2.5)
            if size.height >= 65 {
                Capsule().fill(palette.windowInk.opacity(0.2)).frame(height: 2.5)
                Capsule().fill(palette.windowInk.opacity(0.2))
                    .frame(width: contentWidth * 0.63, height: 2.5)
            }
        }
        .padding(.horizontal, 10).padding(.top, 5)
    }

    private var miniDock: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 5) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.accent.opacity(0.6)).frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.hover, in: RoundedRectangle(cornerRadius: 4))
    }

    private var transitionSymbol: String? {
        switch action {
        case .moveToNextDisplay?: "arrow.right"
        case .restorePreviousFrame?: "arrow.uturn.backward"
        case .minimize?: "arrow.down"
        default: nil
        }
    }
}
