import SwiftUI

/// Permission requests happen only through their buttons; every step can be skipped.
struct OnboardingView: View {
    @EnvironmentObject private var permissionState: PermissionController
    let onFinish: (Bool) -> Void
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Blinker 使用引导", systemImage: "circle.circle")
                    .font(.title2.bold())
                Spacer()
                Text("\(step + 1) / 3").foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(step + 1), total: 3)
                .accessibilityLabel("引导进度")
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    default: gettingStarted
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Button("稍后设置") { onFinish(false) }
                Spacer()
                if step > 0 {
                    Button("上一步") { step -= 1 }
                }
                Button(step == 2 ? String(localized: "完成并打开应用规则") : String(localized: "继续")) {
                    if step == 2 {
                        onFinish(true)
                    } else {
                        step += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear { permissionState.refresh() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("让窗口操作更顺手").font(.title.bold())
            Text("Blinker 常驻菜单栏，应用规则和设置使用独立窗口。")
                .foregroundStyle(.secondary)
            feature("应用规则", symbol: "macwindow.on.rectangle",
                    detail: "按应用设置红、黄、绿按钮的动作；没有规则时保留系统行为。")
            feature("悬停按钮", symbol: "arrow.up.left.and.arrow.down.right",
                    detail: "移到红绿灯上显示更大的按钮，可调整出现延迟和点击保护。")
            feature("预览与切换", symbol: "rectangle.on.rectangle",
                    detail: "悬停 Dock 图标预览窗口，或使用 Option–Tab 切换。")
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按需开启权限").font(.title2.bold())
            ForEach(AppPermission.allCases) { permission in
                GroupBox {
                    PermissionRow(permission: permission, allowsManagement: false).padding(.horizontal, 4)
                }
            }
            PermissionCheckButton()
            Text(permissionState.accessibilityGranted && permissionState.screenRecordingGranted
                ? String(localized: "权限已就绪，可以继续。之后可在「设置 → 隐私与权限」中管理。")
                : String(localized: "点击授权会打开系统设置和可拖拽的应用图标。也可跳过，之后在「设置 → 隐私与权限」中开启。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("从一个应用开始").font(.title.bold())
            feature("添加应用", symbol: "plus.app",
                    detail: "打开应用规则，点击加号选择应用，再为红绿灯选择动作。")
            feature("随时调整或暂停", symbol: "menubar.rectangle",
                    detail: "点击菜单栏图标打开规则；右键可暂停增强功能或进入设置。")
            Button("打开真实测试窗口…") { CompatibilityWindowController.shared.showTestWindow() }
                .disabled(!permissionState.accessibilityGranted)
            Text("可以在测试窗口试用悬停按钮。关闭它不会退出 Blinker。")
                .font(.callout).foregroundStyle(.secondary)
            Text("需要再看一遍时，打开「设置 → 通用 → 重新查看引导」。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func feature(_ title: LocalizedStringKey, symbol: String,
                         detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
