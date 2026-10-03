import AppKit
import BlinkerCore
import SwiftUI
import UniformTypeIdentifiers

/// File panels stay on the main actor; bounded decoding and atomic writes do not.
@MainActor
final class RuleFileActions: ObservableObject {
    enum State: Equatable {
        case idle, choosingImport, choosingExport, importing, exporting, unchanged
        case imported(Int), exported(Int), failed(String)

        var isBusy: Bool {
            switch self {
            case .choosingImport, .choosingExport, .importing, .exporting: true
            default: false
            }
        }

        var isProcessing: Bool {
            self == .importing || self == .exporting
        }

        var message: String {
            switch self {
            case .idle: ""
            case .choosingImport: String(localized: "请选择要导入的规则文件…")
            case .choosingExport: String(localized: "请选择规则文件的保存位置…")
            case .importing: String(localized: "正在读取并验证规则…")
            case .exporting: String(localized: "正在导出规则…")
            case .unchanged: String(localized: "规则没有变化。")
            case let .imported(count): String(localized: "已导入 \(count) 条规则，可撤销。")
            case let .exported(count): String(localized: "已导出 \(count) 条规则。")
            case let .failed(message): message
            }
        }
    }

    typealias Reader = @Sendable (URL) async throws -> [AppRule]
    typealias Writer = @Sendable ([AppRule], URL) async throws -> Void

    @Published private(set) var state = State.idle
    var isBusy: Bool {
        state.isBusy
    }

    private let read: Reader
    private let write: Writer
    private var requestID: UUID?
    private var exportID: UUID?
    private var task: Task<Void, Never>?
    private var panel: NSSavePanel?
    private var closeObserver: NSObjectProtocol?

    init(read: @escaping Reader = { try await RuleFileActions.readFile($0) },
         write: @escaping Writer = { try await RuleFileActions.writeFile($0, $1) }) {
        self.read = read
        self.write = write
    }

    func importRules(into store: RuleStore) {
        guard let request = begin(.choosingImport, owner: NSApp.keyWindow) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "同一应用的规则会被替换，其他规则保留。导入后可撤销。")
        self.panel = panel
        panel.begin { [weak self, weak panel] response in
            guard let self, self.requestID == request else { return }
            guard response == .OK, let url = panel?.url else { self.cancel(); return }
            self.panel = nil
            self.runImport(from: url, into: store, request: request)
        }
    }

    func exportRules(from store: RuleStore) {
        guard let request = begin(.choosingExport, owner: NSApp.keyWindow) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Blinker-rules.json"
        self.panel = panel
        panel.begin { [weak self, weak panel] response in
            guard let self, self.requestID == request else { return }
            guard response == .OK, let url = panel?.url else { self.cancel(); return }
            self.panel = nil
            self.runExport(store.snapshot, to: url, request: request)
        }
    }

    /// Direct URL entry points share the same single-operation gate as the file panels.
    @discardableResult
    func importRules(from url: URL, into store: RuleStore) -> Task<Void, Never>? {
        guard let request = begin(.importing) else { return nil }
        return runImport(from: url, into: store, request: request)
    }

    @discardableResult
    func exportRules(_ rules: [AppRule], to url: URL) -> Task<Void, Never>? {
        guard let request = begin(.exporting) else { return nil }
        return runExport(rules, to: url, request: request)
    }

    func cancel() {
        // Invalidate callbacks before cancelling a panel, which may invoke its completion.
        // An atomic export already in progress may still finish; cancelling does not undo a saved file.
        requestID = nil
        task?.cancel()
        let panel = panel
        self.panel = nil
        panel?.cancel(nil)
        removeCloseObserver()
        // Keep the write gate and its progress until a non-cancellable atomic write finishes.
        if exportID == nil {
            task = nil
            state = .idle
        }
    }

    private func begin(_ state: State, owner: NSWindow? = nil) -> UUID? {
        guard !isBusy else { return nil }
        let request = UUID()
        requestID = request
        self.state = state
        if let owner {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: owner, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
        return request
    }

    @discardableResult
    private func runImport(from url: URL, into store: RuleStore, request: UUID) -> Task<Void, Never> {
        state = .importing
        let read = read
        let task = Task { [weak self, weak store] in
            do {
                let rules = try await read(url)
                guard !Task.isCancelled, let self, self.requestID == request, let store else { return }
                let previous = store.snapshot
                store.merge(rules)
                self.finish(store.snapshot == previous ? .unchanged : .imported(rules.count))
            } catch {
                guard !Task.isCancelled, let self, self.requestID == request else { return }
                self.finish(.failed(error.localizedDescription))
            }
        }
        self.task = task
        return task
    }

    @discardableResult
    private func runExport(_ rules: [AppRule], to url: URL, request: UUID) -> Task<Void, Never> {
        exportID = request
        state = .exporting
        let write = write
        let task = Task { [weak self] in
            let result: State
            do {
                try await write(rules, url)
                result = .exported(rules.count)
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard let self, self.exportID == request else { return }
            self.exportID = nil
            self.finish(self.requestID == request && !Task.isCancelled ? result : .idle)
        }
        self.task = task
        return task
    }

    private func finish(_ state: State) {
        requestID = nil
        task = nil
        removeCloseObserver()
        self.state = state
    }

    private func removeCloseObserver() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
    }

    private nonisolated static func readFile(_ url: URL) async throws -> [AppRule] {
        try await fileWork(at: url) { try RuleTransfer.read(from: url) }
    }

    private nonisolated static func writeFile(_ rules: [AppRule], _ url: URL) async throws {
        try await fileWork(at: url) {
            let data = try RuleTransfer.encode(rules)
            try Task.checkCancellation()
            try data.write(to: url, options: .atomic)
        }
    }

    private nonisolated static func fileWork<Value: Sendable>(
        at url: URL, _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try operation()
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    deinit {
        task?.cancel()
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }
}

struct RuleFileStatus: View {
    @ObservedObject var files: RuleFileActions
    @State private var showingError = false

    var body: some View {
        HStack {
            if files.state.isProcessing {
                OperationProgress(message: files.state.message)
            } else {
                Text(files.state.message)
                    .font(.caption)
                    .foregroundStyle(isFailure ? .red : .secondary)
                    .lineLimit(1)
                    .help(files.state.message)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .accessibilityElement(children: .combine)
        .onChange(of: files.state) { _, _ in showingError = isFailure }
        .alert("规则文件操作失败", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(files.state.message)
        }
    }

    private var isFailure: Bool {
        if case .failed = files.state {
            return true
        }
        return false
    }
}
