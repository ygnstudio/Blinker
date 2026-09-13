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
    public func saveCurrentLayout(named name: String) {
        let entries = WorkspaceManager.captureVisibleWindows()
        if let index = workspaces.firstIndex(where: { $0.name == name }) {
            workspaces[index].entries = entries
        } else {
            workspaces.append(SavedWorkspace(name: name, entries: entries))
        }
        persist()
        logger.info("saved workspace '\(name, privacy: .public)' with \(entries.count) entries")
    }

    /// Re-captures and replaces a stored workspace's entries.
    public func update(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].entries = WorkspaceManager.captureVisibleWindows()
        persist()
    }

    /// Restores a workspace and returns how many windows moved.
    @discardableResult
    public func restore(id: UUID) -> Int {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return 0 }
        let restored = WorkspaceManager.restore(workspace)
        logger.info("restored '\(workspace.name, privacy: .public)': \(restored) windows")
        return restored
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
