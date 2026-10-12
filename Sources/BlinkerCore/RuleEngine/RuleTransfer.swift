import Darwin
import Foundation

public enum RuleTransfer {
    static let maximumBytes = 1_048_576
    static let maximumRules = 1000

    /// A legacy import leaves existing global defaults untouched; v2 carries an explicit replacement.
    public struct Document: Equatable, Sendable {
        public var rules: [AppRule]
        public var globalDefaults: GlobalButtonRules?

        public init(rules: [AppRule], globalDefaults: GlobalButtonRules? = nil) {
            self.rules = rules
            self.globalDefaults = globalDefaults
        }
    }

    public enum ImportError: LocalizedError {
        case invalidArchive
        public var errorDescription: String? {
            String(localized: "规则文件无效、版本不支持或包含重复的应用。", bundle: .module)
        }
    }

    public enum ExportError: LocalizedError, Equatable {
        case invalidRules
        case tooManyRules
        case archiveTooLarge

        public var errorDescription: String? {
            switch self {
            case .invalidRules:
                String(localized: "无法导出：规则无效或包含重复的应用。", bundle: .module)
            case .tooManyRules:
                String(localized: "无法导出：规则数量超过 1000 条上限。", bundle: .module)
            case .archiveTooLarge:
                String(localized: "无法导出：规则文件超过 1 MiB 上限。", bundle: .module)
            }
        }
    }

    /// Legacy API cannot discard an inheritance dependency or the defaults used to resolve it.
    public static func encode(_ rules: [AppRule]) throws -> Data {
        guard rules.allSatisfy({ $0.inheritedSlots.isEmpty }) else { throw ExportError.invalidRules }
        return try encodeArchive(RuleConfigurationArchive(legacyRules: rules))
    }

    public static func encode(_ configuration: RuleConfiguration) throws -> Data {
        try encodeArchive(RuleConfigurationArchive(configuration))
    }

    private static func encodeArchive(_ archive: RuleConfigurationArchive) throws -> Data {
        guard archive.rules.count <= maximumRules else { throw ExportError.tooManyRules }
        guard validRules(archive.rules) else { throw ExportError.invalidRules }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw ExportError.archiveTooLarge }
        return data
    }

    public static func read(from url: URL) throws -> [AppRule] {
        try decode(readData(from: url))
    }

    public static func readConfiguration(from url: URL) throws -> Document {
        try decodeConfiguration(readData(from: url))
    }

    /// Open once, reject special files, and bound both the recorded size and the actual read.
    private static func readData(from url: URL) throws -> Data {
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
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    /// Kept for old callers. v2 must use the complete-document API, never silently lose defaults.
    public static func decode(_ data: Data) throws -> [AppRule] {
        let document = try decodeConfiguration(data)
        guard document.globalDefaults == nil else { throw ImportError.invalidArchive }
        return document.rules
    }

    public static func decodeConfiguration(_ data: Data) throws -> Document {
        guard data.count <= maximumBytes else { throw ImportError.invalidArchive }
        let document = try decodeStoredConfiguration(data)
        guard document.rules.count <= maximumRules else { throw ImportError.invalidArchive }
        return document
    }

    /// Persistence retains historically valid large stores; the smaller bounds apply to file transfer.
    static func decodeStoredConfiguration(_ data: Data) throws -> Document {
        guard let archive = try? JSONDecoder().decode(RuleConfigurationArchive.self, from: data),
              validRules(archive.rules) else { throw ImportError.invalidArchive }
        switch archive.version {
        case 1:
            guard archive.globalDefaults == nil,
                  archive.rules.allSatisfy({ $0.inheritedSlots.isEmpty }) else {
                throw ImportError.invalidArchive
            }
        case RuleConfigurationArchive.currentVersion:
            guard archive.globalDefaults != nil else { throw ImportError.invalidArchive }
        default: throw ImportError.invalidArchive
        }
        return Document(rules: archive.rules, globalDefaults: archive.globalDefaults)
    }

    static func validRules(_ rules: [AppRule]) -> Bool {
        Set(rules.map(\.id)).count == rules.count && rules.allSatisfy { rule in
            !rule.id.isEmpty && rule.id == rule.id.trimmingCharacters(in: .whitespacesAndNewlines)
                && rule.extraVariantActions.values.allSatisfy { !$0.keys.contains(.left) }
                && rule.inheritedSlots.allSatisfy { rule.action(for: $0.button, variant: $0.variant) == nil }
        }
    }

    public static func copying(_ source: AppRule, to target: AppRule) -> AppRule {
        AppRule(bundleIdentifier: target.bundleIdentifier, displayName: target.displayName,
                closeAction: source.closeAction, minimizeAction: source.minimizeAction,
                zoomAction: source.zoomAction, extraVariantActions: source.extraVariantActions,
                isEnabled: source.isEnabled, isHoverEnabled: source.isHoverEnabled,
                inheritedSlots: source.inheritedSlots)
    }
}
