import AppKit
import BlinkerCore
import SwiftUI

/// The detail side of the rules master-detail surface: app identity plus
/// the full click-variant matrix — five click ways by three lights, every
/// slot a full-width picker instead of the old cramped in-row controls.
struct RuleInspectorView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void

    /// Every action is available on every button; the default entry keeps
    /// the system behavior. Menus render the options in titled sections:
    /// default, window ops, snapping, app ops, no-op.
    static let options: [ButtonAction?] = [
        nil,
        .closeWindow,
        .quitApp,
        .minimize,
        .hideApp,
        .maximize,
        .almostMaximize,
        .fullscreen,
        .tileLeft,
        .tileRight,
        .tileTop,
        .tileBottom,
        .tileTopLeft,
        .tileTopRight,
        .tileBottomLeft,
        .tileBottomRight,
        .centerWindow,
        .moveToNextDisplay,
        ButtonAction.none,
    ]

    /// The same options as titled menu sections.
    static let optionGroups: [ActionOptionGroup] = [
        ActionOptionGroup(label: nil, options: [nil]),
        ActionOptionGroup(
            label: tr("窗口", "Window"),
            options: [
                .closeWindow, .minimize, .maximize, .almostMaximize,
                .fullscreen, .centerWindow, .moveToNextDisplay,
            ]
        ),
        ActionOptionGroup(
            label: tr("贴靠", "Snapping"),
            options: [
                .tileLeft, .tileRight, .tileTop, .tileBottom,
                .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight,
            ]
        ),
        ActionOptionGroup(label: tr("应用", "App"), options: [.quitApp, .hideApp]),
        ActionOptionGroup(label: nil, options: [ButtonAction.none]),
    ]

    /// Matrix rows: the plain left click plus every enhanced variant.
    private static let matrixVariants: [ClickVariant] = [.left] + ClickVariant.extraSlots

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                matrix
                Text(tr(
                    "默认保持系统行为；配置长按后，该按钮的普通点击也会由 Blinker 接管。",
                    "Default keeps system behavior; with a long press set,"
                        + " plain clicks on that button are handled by Blinker too."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(rule.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Toggle(tr("启用", "Enabled"), isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    /// The app's cached icon (see `AppIconStore`); no per-render disk I/O.
    private var appIcon: NSImage {
        AppIconStore.icon(forBundleIdentifier: rule.bundleIdentifier)
    }

    // MARK: - Matrix

    /// The localized light name spoken by the matrix pickers' accessibility
    /// labels (mirrors the column headers).
    private func lightName(_ button: TrafficButton) -> String {
        switch button {
        case .close: tr("红灯", "Red")
        case .minimize: tr("黄灯", "Yellow")
        case .zoom: tr("绿灯", "Green")
        }
    }

    private var matrix: some View {
        Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                lightHeader(tr("红灯", "Red"), color: Color(nsColor: .systemRed))
                lightHeader(tr("黄灯", "Yellow"), color: Color(nsColor: .systemYellow))
                lightHeader(tr("绿灯", "Green"), color: Color(nsColor: .systemGreen))
            }
            ForEach(Self.matrixVariants, id: \.rawValue) { variant in
                GridRow {
                    Text(variant.localizedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    cellPicker(button: .close, variant: variant)
                    cellPicker(button: .minimize, variant: variant)
                    cellPicker(button: .zoom, variant: variant)
                }
            }
        }
    }

    private func lightHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func cellPicker(button: TrafficButton, variant: ClickVariant) -> some View {
        // The dot is dropped: the column header already names and colors
        // the light, and the freed width goes to the action label.
        ActionPicker(
            dotColor: .controlAccentColor,
            options: Self.options,
            selection: binding(button: button, variant: variant),
            pickerWidth: 104,
            showsDot: false,
            groups: Self.optionGroups
        )
        // The picker's visible label is the action name; the row/column
        // semantics live in the matrix headers, which VoiceOver does not
        // associate — so name each popup explicitly. The separator is
        // localized so English VoiceOver does not pause on a fullwidth comma.
        .accessibilityLabel("\(variant.localizedLabel)\(tr("，", ", "))\(lightName(button))")
    }

    // MARK: - Bindings

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
