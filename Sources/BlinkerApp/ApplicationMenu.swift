import AppKit

/// Standard responder-chain commands work in every hosted SwiftUI window.
@MainActor
final class ApplicationMenu: NSObject {
    private weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func install() {
        let main = NSMenu()
        let app = submenu("Blinker", in: main)
        add(String(localized: "关于 Blinker"), #selector(about), to: app)
        app.addItem(.separator())
        add(String(localized: "设置…"), #selector(settings), key: ",", to: app)
        app.addItem(.separator())
        let services = submenu(String(localized: "服务"), in: app)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        responder(String(localized: "隐藏 Blinker"), #selector(NSApplication.hide(_:)), key: "h", to: app)
        let hideOthers = responder(
            String(localized: "隐藏其他"), #selector(NSApplication.hideOtherApplications(_:)), key: "h", to: app
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        responder(String(localized: "显示全部"),
                  #selector(NSApplication.unhideAllApplications(_:)), to: app)
        app.addItem(.separator())
        responder(String(localized: "退出 Blinker"),
                  #selector(NSApplication.terminate(_:)), key: "q", to: app)

        let file = submenu(String(localized: "文件"), in: main)
        add(String(localized: "应用规则"), #selector(rules), key: "1", to: file)
        add(String(localized: "添加应用…"), #selector(addApplication), key: "n", to: file)
        file.addItem(.separator())
        responder(String(localized: "关闭窗口"), #selector(NSWindow.performClose(_:)), key: "w", to: file)

        let edit = submenu(String(localized: "编辑"), in: main)
        responder(String(localized: "撤销"), Selector(("undo:")), key: "z", to: edit)
        let redo = responder(String(localized: "重做"), Selector(("redo:")), key: "z", to: edit)
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        responder(String(localized: "剪切"), #selector(NSText.cut(_:)), key: "x", to: edit)
        responder(String(localized: "拷贝"), #selector(NSText.copy(_:)), key: "c", to: edit)
        responder(String(localized: "粘贴"), #selector(NSText.paste(_:)), key: "v", to: edit)
        responder(String(localized: "全选"), #selector(NSText.selectAll(_:)), key: "a", to: edit)

        let window = submenu(String(localized: "窗口"), in: main)
        responder(String(localized: "最小化"), #selector(NSWindow.performMiniaturize(_:)), key: "m", to: window)
        responder(String(localized: "缩放"), #selector(NSWindow.performZoom(_:)), to: window)
        window.addItem(.separator())
        responder(String(localized: "前置全部窗口"), #selector(NSApplication.arrangeInFront(_:)), to: window)
        NSApp.windowsMenu = window

        let help = submenu(String(localized: "帮助"), in: main)
        add(String(localized: "Blinker 使用指南"), #selector(guide), to: help)
        add(String(localized: "重新查看引导"), #selector(onboarding), to: help)
        add(String(localized: "检查应用兼容性…"), #selector(compatibility), to: help)
        add(String(localized: "打开真实测试窗口…"), #selector(testWindow), to: help)
        add(String(localized: "反馈问题"), #selector(feedback), to: help)
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    private func add(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) {
        let item = responder(title, action, key: key, to: menu)
        item.target = self
    }

    @discardableResult
    private func responder(_ title: String, _ action: Selector,
                           key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menu.addItem(item)
        return item
    }

    @objc private func about() { delegate?.openAbout() }
    @objc private func settings() { delegate?.openSettings() }
    @objc private func rules() { delegate?.openApplications() }
    @objc private func addApplication() { delegate?.addApplication() }
    @objc private func onboarding() { delegate?.replayOnboarding() }
    @objc private func compatibility() { CompatibilityWindowController.shared.show() }
    @objc private func testWindow() { CompatibilityWindowController.shared.showTestWindow() }
    @objc private func guide() { if let url = ProjectLinks.guide { NSWorkspace.shared.open(url) } }
    @objc private func feedback() { if let url = ProjectLinks.feedback { NSWorkspace.shared.open(url) } }
}
