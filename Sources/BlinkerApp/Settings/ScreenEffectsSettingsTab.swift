import SwiftUI

struct ScreenEffectsSettingsTab: View {
    @EnvironmentObject private var permissions: PermissionController
    @EnvironmentObject private var assistant: PermissionAssistantController
    @ObservedObject private var controller: ScreenEffectController
    @ObservedObject private var sensor: LidAngleMonitor
    @ObservedObject private var preferences: LidEffectPreferences
    @State private var confirmingReset = false

    init(controller: ScreenEffectController, preferences: LidEffectPreferences? = nil) {
        self.controller = controller
        sensor = controller.sensor
        self.preferences = preferences ?? controller.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            LidEffectPreview(configuration: configuration)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Form {
                statusSection
                Section {
                    Button("应用推荐参数") { preferences.applyRecommended() }
                } header: {
                    Text("参数预设")
                } footer: {
                    Text("兼顾防晃动和连续开合，保留当前启用状态与校准角度。应用后仍可单独调整。")
                }
                ScreenEffectOptions(
                    preferences: preferences,
                    sensor: sensor,
                    onCalibrate: controller.calibrate
                )
                Section {
                    Button("恢复屏幕特效默认设置…") { confirmingReset = true }
                        .disabled(configuration == LidEffectConfiguration())
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            permissions.refresh()
            controller.setInspecting(true)
        }
        .onDisappear { controller.setInspecting(false) }
        .onChange(of: permissions.screenRecordingGranted) { _, _ in controller.refreshPermission() }
        .confirmationDialog("恢复屏幕特效默认设置？", isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button("恢复默认设置", role: .destructive) { preferences.reset() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将关闭 Duo 开合盖效果，并重置校准角度和所有效果参数。")
        }
    }

    private var configuration: LidEffectConfiguration {
        preferences.configuration
    }

    private var statusSection: some View {
        Section {
            Toggle("启用 Duo 开合盖效果", isOn: binding(\.isEnabled))
            LabeledContent("特效状态", value: effectStatus)
            HStack {
                if configuration.isEnabled, controller.errorMessage == nil {
                    Button(controller.isPaused ? String(localized: "继续特效")
                        : String(localized: "暂停特效")) {
                            if controller.isPaused {
                                controller.resume()
                            } else {
                                controller.pause()
                            }
                        }
                        .disabled(controller.isSuspended || controller.reducesMotion)
                }
                if sensor.status == .failed || sensor.status == .unavailable {
                    Button("重试读取角度") { sensor.refresh() }
                        .disabled(controller.isSuspended)
                }
            }
            if let error = controller.errorMessage {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("重试屏幕特效") { controller.resume() }
                    .disabled(!configuration.isEnabled || controller.isSuspended || controller.reducesMotion)
            }
            if !permissions.screenRecordingGranted {
                Text("屏幕特效需要屏幕录制权限；预览和读取开合角度无需此权限。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("授权屏幕特效…") { assistant.show(for: .screenRecording) }
            }
        } header: {
            Text("Duo 开合盖效果")
        } footer: {
            Text("仅作用于内置屏幕，不录音、不保存屏幕画面。可从菜单暂停；按 Esc 暂停其他应用上方的特效需要辅助功能权限。这不是隐私防护。")
        }
    }

    private var effectStatus: String {
        if !configuration.isEnabled {
            return String(localized: "已关闭")
        }
        if controller.reducesMotion {
            return String(localized: "减少动态效果已开启，特效暂停")
        }
        if controller.isSuspended {
            return String(localized: "系统休眠或锁定期间暂停")
        }
        if controller.isPaused {
            return String(localized: "已暂停")
        }
        if !permissions.screenRecordingGranted {
            return String(localized: "等待屏幕录制授权")
        }
        if sensor.status != .available {
            return String(localized: "等待有效的开合角度")
        }
        return controller.isPresenting ? String(localized: "特效运行中") : String(localized: "等待开合动作")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LidEffectConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration[keyPath: keyPath] },
                set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
}
