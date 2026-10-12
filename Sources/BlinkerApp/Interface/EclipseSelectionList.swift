import SwiftUI

/// A lazy selection list whose appearance does not depend on the system List highlight.
/// Filtering only changes visible rows; the owner keeps the full-catalog selection.
struct EclipseSelectionList<Data: RandomAccessCollection, ID: Hashable, Row: View, RowMenu: View>: View {
    @Environment(\.eclipsePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focusedID: ID?
    @State private var hoveredID: ID?
    @State private var focusTarget: ID?
    @State private var focusRequest = UUID()
    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    @Binding private var selection: ID?
    private let isRowEnabled: (Data.Element) -> Bool
    private let row: (Data.Element, Bool) -> Row
    private let rowMenu: (Data.Element) -> RowMenu

    init(_ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<ID?>,
         isRowEnabled: @escaping (Data.Element) -> Bool = { _ in true },
         @ViewBuilder row: @escaping (Data.Element, Bool) -> Row,
         @ViewBuilder contextMenu: @escaping (Data.Element) -> RowMenu) {
        self.data = data
        self.id = id
        _selection = selection
        self.isRowEnabled = isRowEnabled
        self.row = row
        rowMenu = contextMenu
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(data, id: id) { item in
                        selectionButton(for: item)
                            .id(item[keyPath: id])
                    }
                }
                .padding(4)
            }
            .onMoveCommand { move($0, using: proxy) }
            .onChange(of: selection, initial: true) { _, _ in
                if let focusTarget, focusTarget != selection { cancelPendingFocus() }
                revealSelection(using: proxy)
            }
            .onChange(of: visibleIDs) { _, ids in
                if let focusedID, !ids.contains(focusedID) { self.focusedID = nil }
                if let focusTarget, !ids.contains(focusTarget) { cancelPendingFocus() }
                revealSelection(using: proxy)
            }
            .onChange(of: focusedID) { _, target in
                if let target { proxy.scrollTo(target) }
            }
            .task(id: focusRequest) {
                guard let target = focusTarget else { return }
                // Scroll first so an offscreen lazy row can attach its focus binding.
                proxy.scrollTo(target)
                await Task.yield()
                guard !Task.isCancelled, isEnabled, focusTarget == target, selection == target,
                      data.contains(where: { $0[keyPath: id] == target && isRowEnabled($0) }) else { return }
                focusedID = target
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var visibleIDs: [ID] { data.map { $0[keyPath: id] } }

    private func selectionButton(for item: Data.Element) -> some View {
        let itemID = item[keyPath: id]
        let isSelected = selection == itemID
        return Button {
            selection = itemID
            requestFocus(itemID)
        } label: {
            row(item, isSelected)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .foregroundStyle(palette.text)
                .background(isSelected ? palette.selection
                    : hoveredID == itemID ? palette.hover : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if focusedID == itemID {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(palette.accent, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .opacity(isEnabled && isRowEnabled(item) ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($focusedID, equals: itemID)
        .disabled(!isRowEnabled(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            if hovering { hoveredID = itemID } else if hoveredID == itemID { hoveredID = nil }
        }
        .contextMenu { rowMenu(item) }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let selection, visibleIDs.contains(selection) else { return }
        proxy.scrollTo(selection)
    }

    private func cancelPendingFocus() {
        focusTarget = nil
        focusRequest = UUID()
    }

    private func requestFocus(_ target: ID) {
        focusTarget = target
        focusRequest = UUID()
    }

    private func move(_ direction: MoveCommandDirection, using proxy: ScrollViewProxy) {
        guard isEnabled, direction == .up || direction == .down else { return }
        let selectable = data.filter(isRowEnabled).map { $0[keyPath: id] }
        guard !selectable.isEmpty else { return }
        // Selection updates synchronously; focus may trail behind rapid repeated keys.
        // Tab only focuses a button. Space/Return selects it; arrows advance the selection.
        let current = selection.flatMap { selectable.contains($0) ? $0 : nil } ?? focusedID
        let target: ID
        if let current, let index = selectable.firstIndex(of: current) {
            let next = index + (direction == .down ? 1 : -1)
            guard selectable.indices.contains(next) else { return }
            target = selectable[next]
        } else {
            target = direction == .down ? selectable[0] : selectable[selectable.count - 1]
        }
        selection = target
        proxy.scrollTo(target)
        requestFocus(target)
    }
}

extension EclipseSelectionList where RowMenu == EmptyView {
    init(_ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<ID?>,
         isRowEnabled: @escaping (Data.Element) -> Bool = { _ in true },
         @ViewBuilder row: @escaping (Data.Element, Bool) -> Row) {
        self.init(data, id: id, selection: selection, isRowEnabled: isRowEnabled, row: row) { _ in
            EmptyView()
        }
    }
}
