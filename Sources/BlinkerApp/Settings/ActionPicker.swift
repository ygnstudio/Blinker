import AppKit
import BlinkerCore
import SwiftUI

// MARK: - Localized labels

/// Localized label for a remappable action, shared by every picker.
extension ButtonAction {
    var localizedLabel: String {
        switch self {
        case .closeWindow: String(localized: "关闭窗口")
        case .quitApp: String(localized: "退出应用")
        case .minimize: String(localized: "最小化")
        case .hideApp: String(localized: "隐藏应用")
        case .maximize: String(localized: "最大化")
        case .fullscreen: String(localized: "全屏")
        case .tileLeft: String(localized: "左半屏")
        case .tileRight: String(localized: "右半屏")
        case .tileTop: String(localized: "上半屏")
        case .tileBottom: String(localized: "下半屏")
        case .tileTopLeft: String(localized: "左上屏")
        case .tileTopRight: String(localized: "右上屏")
        case .tileBottomLeft: String(localized: "左下屏")
        case .tileBottomRight: String(localized: "右下屏")
        case .centerWindow: String(localized: "窗口居中")
        case .almostMaximize: String(localized: "准最大化")
        case .moveToNextDisplay: String(localized: "下一显示器")
        case .none: String(localized: "无操作")
        case .windowManagerPanel: String(localized: "窗口面板")
        }
    }
}

/// Localized label for a click variant, shown in the rules matrix.
extension ClickVariant {
    var localizedLabel: String {
        switch self {
        case .left: String(localized: "左键")
        case .right: String(localized: "右键")
        case .optionLeft: String(localized: "⌥+左键")
        case .globeLeft: String(localized: "🌐+左键")
        case .longPressLeft: String(localized: "长按")
        }
    }
}

// MARK: - Action picker

/// One titled group of options inside the picker's menu; a `nil` label
/// renders as a plain divider.
struct ActionOptionGroup {
    let label: String?
    let options: [ButtonAction?]
}

/// A traffic-light action picker: a dot in the button's color followed by
/// the action menu, so each row's three pickers are self-explanatory.
struct ActionPicker: View {
    let dotColor: NSColor
    let options: [ButtonAction?]
    @Binding var selection: ButtonAction?
    /// Label for the `nil` option; traffic rows use "默认", extra-button
    /// rows use "不显示".
    var emptyLabel: String = String(localized: "默认")
    /// Minimum menu width; fits four CJK characters ("关闭窗口") without
    /// ellipsis. Uniform across the rules matrix and the hover extra-button
    /// slots (previously the latter used a narrower 88 that truncated
    /// "下一显示器").
    var pickerWidth: CGFloat = 104
    /// Whether the leading color dot renders; matrix cells drop it because
    /// their column headers already carry the light's color.
    var showsDot: Bool = true
    /// Titled groups rendered as menu sections; `nil` keeps the menu flat.
    var groups: [ActionOptionGroup]?

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle()
                    .fill(Color(nsColor: dotColor))
                    .frame(width: 9, height: 9)
            }
            ActionPopupButton(
                options: options,
                emptyLabel: emptyLabel,
                groups: groups,
                selection: $selection
            )
            // Both width bounds: minWidth keeps every Grid column's ideal
            // width equal (all three matrix columns measure ≥104), maxWidth
            // lets the slot — and with it the popup bezel, which always
            // fills its proposed width — stretch with the layout, so every
            // button renders the same width and the chevrons line up.
            .frame(minWidth: pickerWidth, maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - AppKit popup backing

/// The real `NSPopUpButton` behind the action picker.
///
/// SwiftUI's menu-style `Picker` bezel hugs its label under the current
/// macOS design language — fixed frames, minWidth slots and
/// maxWidth-allowing slots all leave the bezel at its content width, so
/// "默认" rendered narrower than "关闭窗口" and the matrix chevrons
/// misaligned. Hosting the AppKit control directly fixes it
/// deterministically: it always fills the width SwiftUI proposes, and it
/// brings the native checkmark and menu sections for free.
private struct ActionPopupButton: NSViewRepresentable {
    let options: [ButtonAction?]
    var emptyLabel: String
    var groups: [ActionOptionGroup]?
    @Binding var selection: ButtonAction?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        // The hosting container is sized by `sizeThatFits` below; the
        // autoresizing mask keeps the bezel filling it on every resize.
        popup.autoresizingMask = [.width, .height]
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        context.coordinator.rebuildMenu(in: popup)
        context.coordinator.syncSelection(in: popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rebuildMenu(in: popup)
        context.coordinator.syncSelection(in: popup)
    }

    /// Fill whatever width the layout proposes; the fitting size is only
    /// the fallback for unsized measurement (Grid's column pass), where the
    /// outer `minWidth: pickerWidth` frame enforces the 104pt floor.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.fittingSize.width,
            height: proposal.height ?? nsView.fittingSize.height
        )
    }

    // MARK: Coordinator

    /// Bridges menu selections into the SwiftUI binding and keeps the
    /// popup's items and checkmark in sync with the binding.
    @MainActor
    final class Coordinator: NSObject {
        var parent: ActionPopupButton
        /// Fingerprint of the menu content the popup was last built from;
        /// rebuilds are skipped while it is unchanged so an open menu is
        /// never torn down mid-tracking.
        private var menuFingerprint = ""

        init(_ parent: ActionPopupButton) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
            let action = rawValue.isEmpty ? nil : ButtonAction(rawValue: rawValue)
            // hop through the main queue: the menu action fires while
            // AppKit is still inside menu tracking, and a synchronous
            // binding write would reenter `updateNSView` mid-run.
            DispatchQueue.main.async { [weak self] in
                self?.parent.selection = action
            }
        }

        func rebuildMenu(in popup: NSPopUpButton) {
            let fingerprint = Self.menuFingerprint(
                options: parent.options,
                emptyLabel: parent.emptyLabel,
                groups: parent.groups
            )
            guard fingerprint != menuFingerprint else { return }
            menuFingerprint = fingerprint

            popup.removeAllItems()
            if let groups = parent.groups {
                for group in groups {
                    if let label = group.label {
                        popup.menu?.addItem(.sectionHeader(title: label))
                    }
                    for action in group.options {
                        popup.menu?.addItem(Self.menuItem(for: action, emptyLabel: parent.emptyLabel))
                    }
                }
            } else {
                for action in parent.options {
                    popup.menu?.addItem(Self.menuItem(for: action, emptyLabel: parent.emptyLabel))
                }
            }
        }

        func syncSelection(in popup: NSPopUpButton) {
            guard Self.action(of: popup.selectedItem) != parent.selection else { return }
            let rawValue = parent.selection?.rawValue ?? ""
            if let index = popup.itemArray.firstIndex(where: {
                ($0.representedObject as? String) == rawValue
            }) {
                popup.selectItem(at: index)
            }
        }

        private static func menuItem(for action: ButtonAction?, emptyLabel: String) -> NSMenuItem {
            // The popup's own target/action (set in `makeNSView`) handles
            // activation, so the item itself carries none; the selection
            // round-trips through the represented raw value, with "" for
            // the nil (system default) entry.
            let item = NSMenuItem(
                title: action?.localizedLabel ?? emptyLabel,
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = action?.rawValue ?? ""
            return item
        }

        private static func action(of item: NSMenuItem?) -> ButtonAction? {
            guard let rawValue = item?.representedObject as? String, !rawValue.isEmpty else { return nil }
            return ButtonAction(rawValue: rawValue)
        }

        private static func menuFingerprint(
            options: [ButtonAction?],
            emptyLabel: String,
            groups: [ActionOptionGroup]?
        ) -> String {
            let optionKey = { (actions: [ButtonAction?]) in
                actions.map { $0?.rawValue ?? "-" }.joined(separator: ",")
            }
            let contentKey = groups.map { groups in
                groups
                    .map { "\($0.label ?? "")|\(optionKey($0.options))" }
                    .joined(separator: ";")
            } ?? optionKey(options)
            return contentKey + "#" + emptyLabel
        }
    }
}
