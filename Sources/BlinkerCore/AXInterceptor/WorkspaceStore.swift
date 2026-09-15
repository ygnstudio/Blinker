import Combine
import Foundation
import os

/// Persists named workspaces in `UserDefaults` and publishes changes for the
/// window-management tab. Capture and restore screen work lives in
/// `WorkspaceManager`.
public final class WorkspaceStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey: String
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "workspace")

    /// All saved workspaces, oldest first.
    @Published public private(set) var workspaces: [SavedWorkspace] = []

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.workspaces"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        workspaces = Self.load(defaults: defaults, key: storageKey)
    }

    /// Snapshots the current window arrangement and saves it under `name`.
    /// Saving again under an existing name overwrites that workspace.
    /// Capture runs on the AX work queue; `completion` fires on the main
    /// thread once the store has been updated.
    public func saveCurrentLayout(named name: String, completion: (() -> Void)? = nil) {
        WorkspaceManager.captureVisibleWindowsAsync { [weak self] entries in
            guard let self else { return }
            if let index = workspaces.firstIndex(where: { $0.name == name }) {
                workspaces[index].entries = entries
            } else {
                workspaces.append(SavedWorkspace(name: name, entries: entries))
            }
            persist()
            logger.info("saved workspace '\(name, privacy: .public)' with \(entries.count) entries")
            completion?()
        }
    }

    /// Re-captures and replaces a stored workspace's entries. Capture runs
    /// on the AX work queue; `completion` fires on the main thread.
    public func update(id: UUID, completion: (() -> Void)? = nil) {
        guard workspaces.contains(where: { $0.id == id }) else {
            completion?()
            return
        }
        WorkspaceManager.captureVisibleWindowsAsync { [weak self] entries in
            guard
                let self,
                let index = workspaces.firstIndex(where: { $0.id == id })
            else {
                completion?()
                return
            }
            workspaces[index].entries = entries
            persist()
            completion?()
        }
    }

    /// Restores a workspace. The AX work runs on the background queue;
    /// `completion` receives how many windows moved, on the main thread.
    public func restore(id: UUID, completion: ((Int) -> Void)? = nil) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            completion?(0)
            return
        }
        WorkspaceManager.restoreAsync(workspace) { [weak self] restored in
            self?.logger.info("restored '\(workspace.name, privacy: .public)': \(restored) windows")
            completion?(restored)
        }
    }

    public func remove(id: UUID) {
        workspaces.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [SavedWorkspace] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedWorkspace].self, from: data)) ?? []
    }
}
