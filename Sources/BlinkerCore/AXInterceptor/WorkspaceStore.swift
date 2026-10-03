import Combine
import Foundation
import os

/// Persists named workspaces in `UserDefaults` and publishes changes for the
/// window-management tab. Capture and restore screen work lives in
/// `WorkspaceManager`.
public final class WorkspaceStore: ObservableObject {
    public enum Operation: Equatable {
        case saving
        case updating(UUID)
        case restoring(UUID)
    }

    @Published public private(set) var operation: Operation?
    public var isBusy: Bool {
        operation != nil
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "workspace")
    private let capture: (@escaping ([WorkspaceEntry]) -> Void) -> Void
    private let restoreLayout: (SavedWorkspace, @escaping (Int) -> Void) -> Void

    /// All saved workspaces, oldest first.
    @Published public private(set) var workspaces: [SavedWorkspace] = []

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.workspaces",
        capture: @escaping (@escaping ([WorkspaceEntry]) -> Void) -> Void = WorkspaceManager
            .captureAllWindowsAsync,
        restore: @escaping (SavedWorkspace, @escaping (Int) -> Void) -> Void = WorkspaceManager.restoreAsync
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.capture = capture
        restoreLayout = restore
        workspaces = Self.load(defaults: defaults, key: storageKey)
    }

    /// Snapshots the current window arrangement and saves it under `name`.
    /// Saving again under an existing name overwrites that workspace.
    /// Capture runs on the AX work queue; `completion` fires on the main
    /// thread once the store has been updated.
    @discardableResult
    public func saveCurrentLayout(named name: String, completion: (() -> Void)? = nil) -> Bool {
        guard !isBusy else { return false }
        operation = .saving
        capture { [weak self] entries in
            guard let self else { return }
            if let index = workspaces.firstIndex(where: { $0.name == name }) {
                workspaces[index].entries = entries
            } else {
                workspaces.append(SavedWorkspace(name: name, entries: entries))
            }
            persist()
            logger.info("saved workspace '\(name, privacy: .public)' with \(entries.count) entries")
            operation = nil
            completion?()
        }
        return true
    }

    /// Re-captures and replaces a stored workspace's entries. Capture runs
    /// on the AX work queue; `completion` fires on the main thread.
    @discardableResult
    public func update(id: UUID, completion: (() -> Void)? = nil) -> Bool {
        guard !isBusy else { return false }
        guard workspaces.contains(where: { $0.id == id }) else {
            completion?()
            return false
        }
        operation = .updating(id)
        capture { [weak self] entries in
            guard
                let self,
                let index = workspaces.firstIndex(where: { $0.id == id })
            else {
                self?.operation = nil
                completion?()
                return
            }
            workspaces[index].entries = entries
            persist()
            operation = nil
            completion?()
        }
        return true
    }

    /// Restores a workspace. The AX work runs on the background queue;
    /// `completion` receives how many windows moved, on the main thread.
    @discardableResult
    public func restore(id: UUID, completion: ((Int) -> Void)? = nil) -> Bool {
        guard !isBusy else { return false }
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            completion?(0)
            return false
        }
        operation = .restoring(id)
        restoreLayout(workspace) { [weak self] restored in
            self?.logger.info("restored '\(workspace.name, privacy: .public)': \(restored) windows")
            self?.operation = nil
            completion?(restored)
        }
        return true
    }

    public func remove(id: UUID) {
        guard !isBusy else { return }
        workspaces.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        storeEncoded(workspaces, forKey: storageKey, in: defaults, category: "workspaces")
    }

    private static func load(defaults: UserDefaults, key: String) -> [SavedWorkspace] {
        guard let data = defaults.data(forKey: key) else { return [] }
        if let workspaces = try? JSONDecoder().decode([SavedWorkspace].self, from: data) {
            return workspaces
        }
        // Quarantine the corrupt blob before starting empty: the next save
        // would otherwise overwrite whatever was recoverable.
        quarantineCorruptBlob(data, forKey: key, in: defaults, category: "workspaces")
        return []
    }
}
