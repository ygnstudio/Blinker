import Darwin
import Foundation

public enum RuleTransfer {
    static let maximumBytes = 1_048_576
    static let maximumRules = 1000

    private struct Archive: Codable {
        let version: Int
        let rules: [AppRule]
    }

    public enum ImportError: LocalizedError {
        case invalidArchive
        public var errorDescription: String? {
            String(localized: "规则文件无效、版本不支持或包含重复的应用。", bundle: .module)
        }
    }

    public static func encode(_ rules: [AppRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Archive(version: 1, rules: rules))
    }

    /// Open once, reject special files, and bound the actual read as well as the
    /// recorded size. A file changing after fstat cannot force an unbounded load.
    public static func read(from url: URL) throws -> [AppRule] {
        guard url.isFileURL else { throw ImportError.invalidArchive }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ImportError.invalidArchive }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw ImportError.invalidArchive }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(65536, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty {
                break
            }
            data.append(chunk)
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> [AppRule] {
        guard data.count <= maximumBytes,
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == 1, archive.rules.count <= maximumRules, validRules(archive.rules)
        else { throw ImportError.invalidArchive }
        return archive.rules
    }

    static func validRules(_ rules: [AppRule]) -> Bool {
        Set(rules.map(\.id)).count == rules.count
            && rules.allSatisfy {
                !$0.id.isEmpty && $0.id == $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.extraVariantActions.values.allSatisfy { !$0.keys.contains(.left) }
            }
    }

    public static func copying(_ source: AppRule, to target: AppRule) -> AppRule {
        AppRule(bundleIdentifier: target.bundleIdentifier, displayName: target.displayName,
                closeAction: source.closeAction, minimizeAction: source.minimizeAction,
                zoomAction: source.zoomAction, extraVariantActions: source.extraVariantActions,
                isEnabled: source.isEnabled, isHoverEnabled: source.isHoverEnabled)
    }
}
