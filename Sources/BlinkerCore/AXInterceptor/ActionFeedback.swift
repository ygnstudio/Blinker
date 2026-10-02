import Foundation

public enum WindowActionResult: Equatable, Sendable {
    case completed
    case permissionRequired
    case unsupportedWindow
    case requestRejected
    case noPreviousLayout
    case noOtherDisplay
    case sizeConstrained

    public var message: String? {
        switch self {
        case .completed: nil
        case .sizeConstrained: String(localized: "应用限制了窗口最小尺寸，已尽量保持窗口可见。", bundle: .module)
        case .permissionRequired: String(localized: "需要辅助功能权限，请在系统设置中重新授权。", bundle: .module)
        case .unsupportedWindow: String(localized: "此窗口不支持该操作，或窗口已关闭。", bundle: .module)
        case .requestRejected: String(localized: "应用未接受操作，请检查窗口是否有待处理的对话框。", bundle: .module)
        case .noPreviousLayout: String(localized: "此窗口没有可还原的布局。", bundle: .module)
        case .noOtherDisplay: String(localized: "未连接其他显示器。", bundle: .module)
        }
    }
}

public enum ActionFeedback {
    public static let notification = Notification.Name("BlinkerActionFeedback")

    public static func report(_ result: WindowActionResult) {
        guard let message = result.message else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: notification, object: nil, userInfo: ["message": message])
        }
    }
}
