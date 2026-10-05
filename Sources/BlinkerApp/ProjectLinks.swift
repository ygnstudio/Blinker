import Foundation

/// Fixed public destinations shared by About, Settings and the Help menu.
enum ProjectLinks {
    static let source = URL(string: "https://github.com/ygnstudio/Blinker")
    static let guide = URL(string: "https://github.com/ygnstudio/Blinker/blob/main/docs/USER_GUIDE.md")
    static let feedback = URL(string: "https://github.com/ygnstudio/Blinker/issues")
    static let social = URL(string: "https://www.xiaohongshu.com/user/profile/66a7e7ae000000001d023641")
    /// System Settings → Privacy & Security → Location Services.
    static let locationPrivacy = URL(string: "x-apple.systempreferences:"
        + "com.apple.preference.security?Privacy_LocationServices")
    /// System Settings → Privacy & Security → Bluetooth.
    static let bluetoothPrivacy = URL(string: "x-apple.systempreferences:"
        + "com.apple.preference.security?Privacy_Bluetooth")
}
