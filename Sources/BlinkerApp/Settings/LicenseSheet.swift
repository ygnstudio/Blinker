import SwiftUI

/// Reads the notices bundled with this exact build, including offline.
struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source = LicenseSource.blinker
    private let texts = Dictionary(uniqueKeysWithValues: LicenseSource.allCases.map { source in
        let text = source.paths.compactMap { path -> String? in
            guard let url = Bundle.main.resourceURL?.appendingPathComponent(path) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n\n")
        return (source, text.isEmpty ? source.identifier : text)
    })

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("许可证").font(.headline)
            Picker("许可证", selection: $source) {
                ForEach(LicenseSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            ScrollView {
                Text(texts[source] ?? source.identifier)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(source)
            HStack {
                if let url = URL(string: source.url) {
                    Link(source.linkTitle, destination: url)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 660, height: 500)
    }
}

private enum LicenseSource: CaseIterable, Hashable {
    case blinker, statusTrio, macbookDuoEffect

    var title: String {
        switch self {
        case .blinker: "Blinker (GPL-3.0-only)"
        case .statusTrio: "Status Trio (Apache-2.0)"
        case .macbookDuoEffect: "Duo Effect (MIT)"
        }
    }

    var identifier: String {
        switch self {
        case .blinker: "GPL-3.0-only"
        case .statusTrio: "Apache-2.0"
        case .macbookDuoEffect: "MIT"
        }
    }

    var paths: [String] {
        switch self {
        case .blinker: ["NOTICE", "LICENSE"]
        case .statusTrio:
            [
                "ThirdParty/StatusTrio/README.md",
                "ThirdParty/StatusTrio/NOTICE",
                "ThirdParty/StatusTrio/LICENSE",
            ]
        case .macbookDuoEffect:
            [
                "ThirdParty/MacbookDuoEffect/README.md",
                "ThirdParty/MacbookDuoEffect/LICENSE",
            ]
        }
    }

    var linkTitle: LocalizedStringKey {
        switch self {
        case .blinker: "GNU 官方许可证"
        case .statusTrio: "Apache 官方许可证"
        case .macbookDuoEffect: "MIT 原始许可证"
        }
    }

    var url: String {
        switch self {
        case .blinker: "https://www.gnu.org/licenses/gpl-3.0.html"
        case .statusTrio: "https://www.apache.org/licenses/LICENSE-2.0"
        case .macbookDuoEffect:
            "https://github.com/RuixiangHuang/Macbook_Duo_Effect/blob/"
                + "af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1/LICENSE"
        }
    }
}
