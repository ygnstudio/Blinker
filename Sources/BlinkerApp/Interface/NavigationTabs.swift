import SwiftUI

/// Selection is a system control, never a hand-built group of competing buttons.
struct NavigationTabs<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> LocalizedStringKey

    var body: some View {
        if #available(macOS 27.0, *) {
            picker.pickerStyle(.tabs)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value)).tag(value)
            }
        }
        .labelsHidden()
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
    }
}
