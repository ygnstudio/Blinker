import SwiftUI

// MARK: - Hotkey row

/// One hotkey binding row: label, current combo (or record prompt), a clear
/// button, plus inline recorder feedback and conflict warnings. Shared by
/// the window-management tab's binding groups and the hover tab's
/// hover-toggle row, so both surfaces keep the same row language.
struct HotkeyRowView: View {
    let label: String
    let combo: HotkeyCombo?
    let isRecording: Bool
    /// Recorder feedback (e.g. "hold a modifier") while this row records.
    let recordingHint: String?
    /// Conflict with another Blinker binding, if any.
    let conflictWarning: String?
    let onRecord: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            // The label never changes while recording — swapping it made the
            // whole row jump; the recording state lives on the chip instead.
            Text(label)
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
            Spacer()
            // Fixed-width trailing column: chip and clear button reserve
            // their space even when absent, so all rows share the same
            // right edge.
            HStack(spacing: 6) {
                Button {
                    onRecord()
                } label: {
                    Text(
                        isRecording
                            ? String(localized: "按下快捷键…")
                            : combo?.displayLabel ?? String(localized: "未设置")
                    )
                    // Wide enough for the recording prompt ("按下快捷键…")
                    // and four-modifier combos ("⌃⌥⇧⌘K"), so no row ellipsizes
                    // and all rows keep a shared right edge.
                    .frame(width: 96)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                Button(role: .destructive, action: onClear) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("清除快捷键")
                .accessibilityLabel("清除快捷键")
                .disabled(combo == nil)
                .opacity(combo == nil ? 0 : 1)
            }
        }
        if isRecording {
            // Recorder feedback: the reject reason when the last press was
            // unusable, otherwise the visible cancel affordance.
            Text(recordingHint ?? String(localized: "按 Esc 取消录制"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let conflictWarning {
            WarningLine(text: conflictWarning)
        }
        if let combo, let warning = HotkeyManager.systemConflictWarning(for: combo) {
            WarningLine(text: warning)
        }
    }
}

// MARK: - Warning line

/// A small warning line: primary-color text (contrast-safe in both
/// appearances) with a decorative orange glyph carrying the tone.
struct WarningLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.primary)
        }
    }
}
