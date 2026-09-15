import AppKit
import BlinkerCore
import SwiftUI

// MARK: - Localized labels

/// Localized label for a remappable action, shared by every picker.
extension ButtonAction {
    var localizedLabel: String {
        switch self {
        case .closeWindow: tr("关闭窗口", "Close Window")
        case .quitApp: tr("退出应用", "Quit App")
        case .minimize: tr("最小化", "Minimize")
        case .hideApp: tr("隐藏应用", "Hide App")
        case .maximize: tr("最大化", "Maximize")
        case .fullscreen: tr("全屏", "Fullscreen")
        case .tileLeft: tr("左半屏", "Tile Left")
        case .tileRight: tr("右半屏", "Tile Right")
        case .tileTop: tr("上半屏", "Tile Top")
        case .tileBottom: tr("下半屏", "Tile Bottom")
        case .tileTopLeft: tr("左上屏", "Tile Top Left")
        case .tileTopRight: tr("右上屏", "Tile Top Right")
        case .tileBottomLeft: tr("左下屏", "Tile Bottom Left")
        case .tileBottomRight: tr("右下屏", "Tile Bottom Right")
        case .centerWindow: tr("窗口居中", "Center")
        case .almostMaximize: tr("准最大化", "Almost Maximize")
        case .moveToNextDisplay: tr("移到下一显示器", "Next Display")
        case .none: tr("无操作", "Do Nothing")
        case .windowManagerPanel: tr("窗口管理", "Window Manager")
        }
    }
}

/// Localized label for a click variant, shown in the rules matrix.
extension ClickVariant {
    var localizedLabel: String {
        switch self {
        case .left: tr("左键", "Left Click")
        case .right: tr("右键", "Right Click")
        case .optionLeft: tr("⌥ + 左键", "⌥ + Left Click")
        case .globeLeft: tr("🌐 + 左键", "🌐 + Left Click")
        case .longPressLeft: tr("长按", "Long Press")
        }
    }
}

// MARK: - Action picker

/// A traffic-light action picker: a dot in the button's color followed by
/// the action menu, so each row's three pickers are self-explanatory.
struct ActionPicker: View {
    let dotColor: NSColor
    let options: [ButtonAction?]
    @Binding var selection: ButtonAction?
    /// Label for the `nil` option; traffic rows use "默认", extra-button
    /// rows use "不显示".
    var emptyLabel: String = tr("默认", "Default")
    /// Menu width; fits four CJK characters ("关闭窗口") without ellipsis.
    /// The compact variant matrix uses a narrower value.
    var pickerWidth: CGFloat = 88

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(nsColor: dotColor))
                .frame(width: 9, height: 9)
            Picker(selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, action in
                    Text(Self.label(for: action, emptyLabel: emptyLabel)).tag(action)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(width: pickerWidth)
        }
    }

    private static func label(for action: ButtonAction?, emptyLabel: String) -> String {
        guard let action else { return emptyLabel }
        return action.localizedLabel
    }
}
