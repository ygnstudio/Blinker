import AppKit
import BlinkerCore
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    let onShowOnboarding: () -> Void
    let onShowAbout: () -> Void
    @EnvironmentObject var coordinator: InterceptionCoordinator
    @EnvironmentObject private var permissionAssistant: PermissionAssistantController
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var feedback = ActionFeedbackController.shared
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError = false

    var body: some View {
        Form {
            Section {
                Toggle("启用 Blinker", isOn: Binding(
                    get: { coordinator.isIntercepting },
                    set: {
                        if coordinator.isIntercepting != $0 {
                            coordinator.toggle()
                        }
                    }
                ))
                LabeledContent("状态", value: coordinator.status.localizedLabel)
                if coordinator.status == .noPermission {
                    Button("授权辅助功能…") { permissionAssistant.show(for: .accessibility) }
                } else if coordinator.status == .tapFailed || coordinator.status == .partial {
                    Button("重试启动拦截") {
                        coordinator.stop()
                        coordinator.start()
                    }
                }
            } header: {
                Text("运行状态")
            } footer: {
                Text("暂停全部增强功能，保留应用规则和偏好设置。")
            }

            Section {
                Picker("外观", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.menuLabel).tag(appearance)
                    }
                }
                Picker("语言", selection: $preferences.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.menuLabel).tag(language)
                    }
                }
            } header: {
                Text("外观与语言")
            } footer: {
                if preferences.languageNeedsRestart {
                    Text("语言设置已保存，退出并重新打开 Blinker 后生效。")
                }
            }

            Section("启动") {
                Toggle("登录时启动 Blinker", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: updateLaunchAtLogin
                ))
                if loginStatus == .requiresApproval {
                    Button("在系统设置中允许登录项…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if loginError {
                    Text("注册登录自启失败，请重试或检查系统设置 → 通用 → 登录项。")
                        .foregroundStyle(.red)
                }
            }

            Section("使用帮助") {
                if let url = ProjectLinks.guide {
                    Link("使用指南", destination: url)
                }
                Button("重新查看引导", action: onShowOnboarding)
                Button("关于 Blinker", action: onShowAbout)
            }

            if !coordinator.moduleIssues.isEmpty || feedback.latestMessage != nil {
                Section("诊断") {
                    ForEach(coordinator.moduleIssues, id: \.self) { Text($0).foregroundStyle(.orange) }
                    if let message = feedback.latestMessage {
                        LabeledContent("最近操作反馈", value: message)
                    }
                    Button("检查应用兼容性…") { CompatibilityWindowController.shared.show() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            refreshLoginStatus()
        }
    }

    private func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    /// Only the binding setter registers a login item; observing system state never writes it back.
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = false
        } catch {
            loginError = true
        }
        refreshLoginStatus()
    }
}
