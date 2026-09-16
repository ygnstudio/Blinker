import AppKit
import BlinkerCore
import SwiftUI

/// The detail side of the rules master-detail surface, redesigned around the
/// traffic-light motif:
///
/// * a **signal card** — the app's identity plus three vivid dots each
///   naming its current left-click action, so "what do this app's lights
///   do" answers at a glance;
/// * a **lane matrix** — five click variants by three lights, organized as
///   red/amber/green tinted lanes of bezel-free menu cells instead of a
///   wall of popup buttons.
///
/// Alignment is the load-bearing wall: the label column and every lane are
/// built from the same fixed row heights (`MatrixMetrics`), so the five
/// variant rows line up across all four columns at any window width.
struct RuleInspectorView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void

    /// The same titled menu sections as every action picker.
    static let optionGroups: [ActionOptionGroup] = [
        ActionOptionGroup(label: nil, options: [nil]),
        ActionOptionGroup(
            label: String(localized: "窗口"),
            options: [
                .closeWindow, .minimize, .maximize, .almostMaximize,
                .fullscreen, .centerWindow, .moveToNextDisplay,
            ]
        ),
        ActionOptionGroup(
            label: String(localized: "贴靠"),
            options: [
                .tileLeft, .tileRight, .tileTop, .tileBottom,
                .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight,
            ]
        ),
        ActionOptionGroup(label: String(localized: "应用"), options: [.quitApp, .hideApp]),
        ActionOptionGroup(label: nil, options: [ButtonAction.none]),
    ]

    /// Matrix rows: the plain left click plus every enhanced variant.
    private static let matrixVariants: [ClickVariant] = [.left] + ClickVariant.extraSlots

    /// Fixed metrics shared by the label column and the three lanes so every
    /// row stays on one baseline across the whole matrix.
    private enum MatrixMetrics {
        static let labelColumnWidth: CGFloat = 62
        static let rowHeight: CGFloat = 30
        static let headerHeight: CGFloat = 26
        static let columnSpacing: CGFloat = 10
    }

    var body: some View {
        Form {
            Section {
                signalCard
            }
            Section {
                laneMatrix
            } header: {
                SectionHeader(title: String(localized: "动作矩阵"), info: longPressNote)
            }
        }
        .formStyle(.grouped)
    }

    /// The long-press side effect, surfaced from the matrix section header's
    /// info popover (the app-wide convention for long explanations) instead
    /// of a low-weight caption below the grid.
    private var longPressNote: String {
        String(localized: "左键行即上方摘要；配置长按后，该按钮的普通点击也会由 Blinker 接管。")
    }

    // MARK: - Signal card

    /// The app's identity row plus the three-light summary: each vivid dot
    /// with its light name and current left-click action. The one place in
    /// the window where the product's motif carries real information.
    private var signalCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(rule.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Toggle("开启", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "开启规则"))
            }
            Divider()
                .padding(.vertical, 12)
            HStack(spacing: 0) {
                ForEach(TrafficButton.allCases, id: \.self) { button in
                    signalLight(button)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One light of the summary: vivid dot + glyph, light name, left-click
    /// action. Single-line everywhere so the three columns stay aligned.
    private func signalLight(_ button: TrafficButton) -> some View {
        let color = vividColor(button)
        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 17, height: 17)
                    .shadow(color: color.opacity(0.45), radius: 5)
                TrafficLightGlyph(button: button)
                    .frame(width: 10, height: 10)
            }
            .frame(height: 17)
            Text(lightName(button))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(leftClickSummary(for: button))
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The light's left-click action, or "系统默认" when untouched.
    private func leftClickSummary(for button: TrafficButton) -> String {
        rule.action(for: button, variant: .left)?.localizedLabel
            ?? String(localized: "系统默认")
    }

    /// The app's cached icon (see `AppIconStore`); no per-render disk I/O.
    private var appIcon: NSImage {
        AppIconStore.icon(forBundleIdentifier: rule.bundleIdentifier)
    }

    // MARK: - Lane matrix

    /// The full click-variant matrix as three color-tinted lanes plus the
    /// right-aligned variant label column.
    private var laneMatrix: some View {
        HStack(alignment: .top, spacing: MatrixMetrics.columnSpacing) {
            variantLabels
            lane(for: .close)
            lane(for: .minimize)
            lane(for: .zoom)
        }
    }

    /// The variant label column — same row heights and top padding as the
    /// lanes, so all five labels sit exactly level with their menu cells.
    private var variantLabels: some View {
        VStack(spacing: 1) {
            Color.clear
                .frame(height: MatrixMetrics.headerHeight)
            ForEach(Self.matrixVariants, id: \.rawValue) { variant in
                Text(variant.localizedLabel)
                    .font(variant == .left ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(variant == .left ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(
                        width: MatrixMetrics.labelColumnWidth,
                        height: MatrixMetrics.rowHeight,
                        alignment: .trailing
                    )
            }
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    /// One light's lane: a tinted rounded column carrying the light's header
    /// and its five flat menu cells. The tint is the only decoration — it
    /// encodes which light the column configures.
    private func lane(for button: TrafficButton) -> some View {
        let color = vividColor(button)
        return VStack(spacing: 1) {
            laneHeader(button)
                .frame(height: MatrixMetrics.headerHeight)
            ForEach(Self.matrixVariants, id: \.rawValue) { variant in
                FlatActionMenu(
                    groups: Self.optionGroups,
                    selection: binding(button: button, variant: variant)
                )
                .frame(height: MatrixMetrics.rowHeight)
                .accessibilityLabel(
                    "\(variant.localizedLabel)\(String(localized: "，"))\(lightName(button))"
                )
            }
        }
        .padding(EdgeInsets(top: 4, leading: 7, bottom: 7, trailing: 7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }

    /// The lane's header: the light's vivid dot and localized name.
    private func laneHeader(_ button: TrafficButton) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vividColor(button))
                .frame(width: 8, height: 8)
            Text(lightName(button))
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    /// The overlay's vivid fill color for a light, shared with the hover
    /// chips so the settings preview and the real overlay agree.
    private func vividColor(_ button: TrafficButton) -> Color {
        Color(nsColor: OverlayChipDrawing.vividColor(for: button))
    }

    // MARK: - Names and bindings

    /// The localized light name spoken by the matrix cells' accessibility
    /// labels (mirrors the lane headers).
    private func lightName(_ button: TrafficButton) -> String {
        switch button {
        case .close: String(localized: "红灯")
        case .minimize: String(localized: "黄灯")
        case .zoom: String(localized: "绿灯")
        }
    }

    private func binding(button: TrafficButton, variant: ClickVariant) -> Binding<ButtonAction?> {
        Binding(
            get: { rule.action(for: button, variant: variant) },
            set: { newValue in
                var updated = rule
                updated.setAction(newValue, button: button, variant: variant)
                onUpdate(updated)
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { newValue in
                var updated = rule
                updated.isEnabled = newValue
                onUpdate(updated)
            }
        )
    }
}
