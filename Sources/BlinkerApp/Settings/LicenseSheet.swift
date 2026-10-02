import SwiftUI

/// Reads the notices bundled with this exact build, including offline.
struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let text = ["NOTICE", "LICENSE"].compactMap { name in
        Bundle.main.url(forResource: name, withExtension: nil).flatMap {
            try? String(contentsOf: $0, encoding: .utf8)
        }
    }.joined(separator: "\n\n")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GNU General Public License v3.0").font(.headline)
            ScrollView {
                Text(text.isEmpty ? "GPL-3.0-only" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if let url = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") {
                    Link("GNU 官方许可证", destination: url)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 660, height: 500)
    }
}
