import AppKit
import BlinkerCore
import SwiftUI

/// The detail side of the rules master-detail surface: app identity plus
/// the full click-variant matrix — five click ways by three lights, every
/// slot a full-width picker instead of the old cramped in-row controls.
/// Header and matrix sit in grouped form cards so the inspector shares the
/// card language of every other tab; the master-detail split stays.
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

    var body: some View {
        Form {
            Section {
                header
            }
            Section {
                matrix
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
        String(localized: "默认保持系统行为；配置长按后，该按钮的普通点击也会由 Blinker 接管。")
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
            Toggle("开启", isOn: enabledBinding)
                .toggleStyle(.switch)
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
        case .close: String(localized: "红灯")
        case .minimize: String(localized: "黄灯")
        case .zoom: String(localized: "绿灯")
        }
    }

    private var matrix: some View {
        Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                lightHeader("红灯", color: Color(nsColor: .systemRed))
                lightHeader("黄灯", color: Color(nsColor: .systemYellow))
                lightHeader("绿灯", color: Color(nsColor: .systemGreen))
            }
            ForEach(Self.matrixVariants, id: \.rawValue) { variant in
                GridRow {
                    // Fixed-width label column: without it "⌥+左键" and
                    // "🌐+左键" wrap to two lines while the others stay on
                    // one, misaligning the whole grid. Scaling (instead of
                    // truncation) absorbs longer English labels.
                    Text(variant.localizedLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 64, alignment: .trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    cellPicker(button: .close, variant: variant)
                    cellPicker(button: .minimize, variant: variant)
                    cellPicker(button: .zoom, variant: variant)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityLabel("\(variant.localizedLabel)\(String(localized: "，"))\(lightName(button))")
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
