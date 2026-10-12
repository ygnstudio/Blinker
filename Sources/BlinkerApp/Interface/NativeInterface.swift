import SwiftUI

/// One form style owns section surfaces and preserves the original native controls.
struct NativeFormSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .formStyle(EclipseFormStyle())
            .scrollContentBackground(.hidden)
            .frame(minWidth: 0, maxWidth: 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
