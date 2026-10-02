import ApplicationServices
import Foundation

/// Reads native tab bars only; never descends into webpage or document content.
/// Owned by WindowDiscovery's serial queue, with bounded AX work per window.
enum WindowTabDiscovery {
    struct Tab {
        let element: AXUIElement
        let title: String
        let selected: Bool
    }

    private struct Node {
        let element: AXUIElement
        let depth: Int
        let toolbar: Bool
    }

    struct StandardTabDescriptor {
        let title: String
        let selected: Bool
        let hasCloseControl: Bool
    }

    /// Native AppKit document tabs are a window-owned bar with closable items.
    /// A plain NSTabView in a settings/content hierarchy must remain one window.
    static func isDocumentTabBar(isWindowChild: Bool, tabs: [StandardTabDescriptor]) -> Bool {
        isWindowChild && tabs.count > 1 && tabs.filter(\.selected).count == 1
            && tabs.allSatisfy { !$0.title.isEmpty && $0.hasCloseControl }
    }

    static func tabs(in window: AXUIElement, bundleID: String) -> [Tab] {
        let reader = Reader()
        for group in reader.elements(window, kAXChildrenAttribute).prefix(80) {
            guard reader.available else { return [] }
            guard reader.string(group, kAXRoleAttribute) == kAXTabGroupRole else { continue }
            let tabs = nativeTabs(group, role: kAXTabGroupRole,
                                  children: reader.elements(group, kAXChildrenAttribute),
                                  toolbar: false, reader: reader)
            let descriptors = tabs.map { tab in
                StandardTabDescriptor(title: tab.title, selected: tab.selected,
                                      hasCloseControl: reader.elements(tab.element, kAXChildrenAttribute)
                                          .contains {
                                              reader.string($0, kAXRoleAttribute) == kAXButtonRole
                                          })
            }
            if reader.available, isDocumentTabBar(isWindowChild: true, tabs: descriptors) {
                return tabs
            }
        }
        // Safari's tab buttons live in a native toolbar provider, not an AppKit
        // window tab bar. Keep that exception scoped to Safari.
        return bundleID == "com.apple.Safari" ? safariTabs(in: window, reader: reader) : []
    }

    private static func safariTabs(in window: AXUIElement, reader: Reader) -> [Tab] {
        var pending = [Node(element: window, depth: 0, toolbar: false)]
        var visited = 0
        while visited < pending.count, visited < 80, reader.available {
            let node = pending[visited]
            let element = node.element
            visited += 1
            let role = reader.string(element, kAXRoleAttribute) ?? ""
            let toolbar = node.toolbar || role == kAXToolbarRole
            let children = reader.elements(element, kAXChildrenAttribute)
            let tabs = nativeTabs(element, role: role, children: children, toolbar: toolbar, reader: reader)
            if !tabs.isEmpty, reader.available {
                return tabs
            }
            let toolbarContainer = toolbar && ["AXOpaqueProviderGroup", kAXScrollAreaRole].contains(role)
            guard node.depth < 9, shouldTraverse(role) || toolbarContainer else { continue }
            pending.append(contentsOf: children.prefix(max(0, 80 - pending.count)).map { Node(
                element: $0,
                depth: node.depth + 1,
                toolbar: toolbar
            ) })
        }
        return []
    }

    private static func nativeTabs(_ element: AXUIElement, role: String,
                                   children: [AXUIElement], toolbar: Bool, reader: Reader) -> [Tab] {
        let standard = role == kAXTabGroupRole
        guard standard || toolbar else { return [] }
        let explicit = standard ? reader.elements(element, kAXTabsAttribute) : []
        let tabs = explicit.isEmpty ? children.filter {
            let role = reader.string($0, kAXRoleAttribute) ?? ""
            let tabRole = role == kAXRadioButtonRole || role == "AXTab"
                || reader.string($0, kAXSubroleAttribute) == "AXTabButton"
            return tabRole && (standard || reader.string($0, kAXIdentifierAttribute)?
                .hasPrefix("TabBarTab") == true)
        } : explicit
        return tabs.compactMap { tab in
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let title = reader.string(tab, attribute), !title.isEmpty {
                    return Tab(element: tab, title: title, selected: reader.selected(tab))
                }
            }
            return nil
        }
    }

    private static func shouldTraverse(_ role: String) -> Bool {
        // Skip AXWebArea, document scroll areas and outlines. Safari's native
        // toolbar has its own provider/scroll containers, handled above.
        [kAXWindowRole, kAXGroupRole, kAXSplitGroupRole, kAXToolbarRole, kAXTabGroupRole].contains(role)
    }

    static func isSelected(_ tab: AXUIElement) -> Bool {
        Reader().selected(tab)
    }

    private final class Reader {
        var budget = WindowAXReadBudget()
        var available: Bool {
            budget.isAvailable
        }

        private func prepare(_ element: AXUIElement) -> Bool {
            guard let timeout = budget.nextTimeout() else { return false }
            return AXUIElementSetMessagingTimeout(element, timeout) == .success
        }

        func string(_ element: AXUIElement, _ attribute: String) -> String? {
            guard prepare(element) else { return nil }
            return AXQuery.stringAttribute(element, attribute)
        }

        func selected(_ tab: AXUIElement) -> Bool {
            for attribute in [kAXSelectedAttribute, kAXValueAttribute] {
                guard prepare(tab) else { return false }
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(tab, attribute as CFString, &value) == .success
                else { continue }
                if let number = value as? NSNumber, number.boolValue {
                    return true
                }
                if let string = value as? String,
                   ["1", "true", "on"].contains(string.lowercased()) {
                    return true
                }
            }
            return false
        }

        func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
            guard prepare(element) else { return [] }
            var count = 0
            guard AXUIElementGetAttributeValueCount(element, attribute as CFString, &count) == .success,
                  count > 0, count <= 256, prepare(element) else { return [] }
            var values: CFArray?
            guard AXUIElementCopyAttributeValues(
                element, attribute as CFString, 0, count, &values
            ) == .success else { return [] }
            return values as? [AXUIElement] ?? []
        }
    }
}
