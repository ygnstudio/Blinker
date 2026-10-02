import AppKit
import BlinkerCore
import SwiftUI

/// A native popup that fills its grid column, including short labels such as “不显示”.
struct ActionPicker: NSViewRepresentable {
    let options: [ButtonAction?]
    @Binding var selection: ButtonAction?
    var emptyLabel: String = .init(localized: "默认")

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        context.coordinator.update(popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(popup)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context _: Context) -> CGSize? {
        CGSize(width: max(104, proposal.width ?? nsView.fittingSize.width), height: nsView.fittingSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ActionPicker
        private var displayedOptions: [ButtonAction?]?
        private var displayedEmptyLabel: String?

        init(_ parent: ActionPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
            let action = rawValue.isEmpty ? nil : ButtonAction(rawValue: rawValue)
            // Leave AppKit's menu tracking before changing the SwiftUI binding.
            DispatchQueue.main.async { [weak self] in self?.parent.selection = action }
        }

        func update(_ popup: NSPopUpButton) {
            // Avoid rebuilding an open menu for unrelated preference changes.
            if displayedOptions != parent.options || displayedEmptyLabel != parent.emptyLabel {
                displayedOptions = parent.options
                displayedEmptyLabel = parent.emptyLabel
                popup.removeAllItems()
                for action in parent.options {
                    let item = NSMenuItem(title: action?.localizedLabel ?? parent.emptyLabel,
                                          action: nil, keyEquivalent: "")
                    item.representedObject = action?.rawValue ?? ""
                    popup.menu?.addItem(item)
                }
            }
            let selectedValue = parent.selection?.rawValue ?? ""
            if popup.selectedItem?.representedObject as? String != selectedValue,
               let index = popup.itemArray.firstIndex(where: {
                   ($0.representedObject as? String) == selectedValue
               }) {
                popup.selectItem(at: index)
            }
        }
    }
}
