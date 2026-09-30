import AppKit
import BlinkerCore
import SwiftUI
import UniformTypeIdentifiers

/// File panels stay on the main actor; bounded decoding and atomic writes do not.
@MainActor
final class RuleFileActions: ObservableObject {
    @Published private(set) var isBusy = false

    func importRules(into store: RuleStore) {
        guard !isBusy else { return }
        isBusy = true
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "同一应用的规则会被替换，其他规则保留。导入后可撤销。")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { self.isBusy = false; return }
            Task {
                defer { self.isBusy = false }
                do {
                    let rules = try await Task.detached(priority: .userInitiated) {
                        try RuleTransfer.read(from: url)
                    }.value
                    store.merge(rules)
                } catch { self.show(error) }
            }
        }
    }

    func exportRules(from store: RuleStore) {
        guard !isBusy else { return }
        isBusy = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Blinker-rules.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { self.isBusy = false; return }
            let rules = store.snapshot
            Task {
                defer { self.isBusy = false }
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try RuleTransfer.encode(rules).write(to: url, options: .atomic)
                    }.value
                } catch { self.show(error) }
            }
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
