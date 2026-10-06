import SwiftUI

/// The quick actions block: microphone mute for the default input, display
/// and keyboard cleaning overlays, and the user's named Shortcut slots.
/// Rows the user hides in settings simply leave the block out; an entirely
/// empty block hides the section.
extension SystemStatusPanel {
    enum ShortcutSlotState: Equatable {
        case idle, running, failed(ShortcutRunner.Failure)
    }

    /// True when at least one quick action row is configured to show.
    var quickActionsHasRows: Bool {
        let configuration = preferences.configuration
        return configuration.showsQuickActionMicMute
            || configuration.showsQuickActionDisplayCleaning
            || configuration.showsQuickActionKeyboardCleaning
            || !configuration.shortcutSlots.isEmpty
    }

    /// The panel's second page. An entirely unconfigured page still keeps its
    /// heading gear so the way back to settings stays discoverable.
    var quickActionsPage: some View {
        VStack(alignment: .leading,
               spacing: preferences.configuration.panelDensity.sectionSpacing) {
            if quickActionsHasRows {
                quickActionsSection
            } else {
                heading("快速操作", symbol: "bolt.circle", page: .quickActions)
                Text("没有已开启的操作，可在快速操作设置中开启。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    var quickActionsSection: some View {
        let configuration = preferences.configuration
        if quickActionsHasRows {
            VStack(alignment: .leading,
                   spacing: configuration.panelDensity.rowSpacing) {
                heading("快速操作", symbol: "bolt.circle", page: .quickActions)
                if configuration.showsQuickActionMicMute {
                    micMuteRow
                }
                if configuration.showsQuickActionDisplayCleaning {
                    cleaningRow(title: LocalizedStringKey("显示器清洁模式"), symbol: "display",
                                help: String(localized: "全屏黑屏并锁定键盘；按 Esc 或点击退出")) {
                        cleaning.start(.display)
                    }
                }
                if configuration.showsQuickActionKeyboardCleaning {
                    cleaningRow(title: LocalizedStringKey("键盘清洁模式"), symbol: "keyboard",
                                help: String(localized: "系统级锁定键盘输入；点击退出按钮或连按三次 Esc 结束")) {
                        cleaning.start(.keyboard)
                    }
                }
                ForEach(configuration.shortcutSlots, id: \.self, content: shortcutRow)
            }
        }
    }

    private var micMuteRow: some View {
        HStack(spacing: 6) {
            Image(systemName: audio.input?.isMuted == true ? "mic.slash.fill" : "mic.fill")
                .frame(width: 18)
                .foregroundStyle(audio.input?.isMuted == true ? Color.orange : Color.primary)
            Text("麦克风")
            if audio.input?.isMuted == true {
                Text("已静音")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Toggle("麦克风静音", isOn: micMuteBinding)
                .toggleStyle(.switch).labelsHidden()
                .disabled(audio.input?.canMute != true)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var micMuteBinding: Binding<Bool> {
        Binding(get: { audio.input?.isMuted == true },
                set: { audio.setInputMuted($0) })
    }

    private func cleaningRow(title: LocalizedStringKey, symbol: String, help: String,
                             action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Button("开始", action: action)
                .buttonStyle(.borderless)
                .help(help)
        }
        .font(.callout)
    }

    private func shortcutRow(_ name: String) -> some View {
        let state = shortcutSlotStates[name] ?? .idle
        return HStack(spacing: 6) {
            Image(systemName: "command").frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if case .failed(let failure) = state {
                    Text(failureMessage(failure))
                        .font(.caption).foregroundStyle(.red)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if state == .running {
                ProgressView().controlSize(.small)
            } else {
                Button("运行") { runShortcut(name) }
                    .buttonStyle(.borderless)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func runShortcut(_ name: String) {
        guard shortcutSlotStates[name] != .running else { return }
        shortcutSlotStates[name] = .running
        shortcutRunner.run(name) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    shortcutSlotStates[name] = .idle
                case .failure(let failure):
                    shortcutSlotStates[name] = .failed(failure)
                }
            }
        }
    }

    private func failureMessage(_ failure: ShortcutRunner.Failure) -> String {
        switch failure {
        case .notFound:
            String(localized: "未找到同名快捷指令")
        case .timedOut:
            String(localized: "运行超时")
        case .failed(let message):
            String(localized: "运行失败：\(message)")
        }
    }
}
