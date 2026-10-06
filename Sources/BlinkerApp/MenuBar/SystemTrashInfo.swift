import Foundation

/// Item count and emptying for the quick actions block's trash row. Pure
/// `FileManager`, no permission, no subprocess: the boot volume's per-user
/// trash is not a TCC-protected location. External volumes keep their own
/// `.Trashes` — touching those would raise the removable-volume prompt, so
/// the row only ever empties the startup disk's trash.
enum SystemTrashInfo {
    /// The current user's trash on the boot volume (`~/.Trash` unsandboxed).
    static let trashURL = FileManager.default
        .urls(for: .trashDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")

    /// Top-level entries, hidden files included: that is exactly what
    /// `empty` deletes, so the count never disagrees with the outcome.
    static func itemCount(at url: URL = trashURL) -> Int {
        let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)
        return items?.count ?? 0
    }

    struct EmptyReport: Equatable, Sendable {
        var emptied: Int
        /// Items the system refused to remove — usually in use or locked.
        var failed: Int
    }

    /// Deletes every top-level entry. A missing or unreadable trash reads as
    /// empty rather than failing. Items in use or locked stay behind and are
    /// counted in `failed`; the row reports them instead of retrying.
    static func empty(at url: URL = trashURL) -> EmptyReport {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)
        else { return EmptyReport(emptied: 0, failed: 0) }
        var emptied = 0
        var failed = 0
        for item in items {
            if (try? manager.removeItem(at: item)) != nil {
                emptied += 1
            } else {
                failed += 1
            }
        }
        return EmptyReport(emptied: emptied, failed: failed)
    }
}

/// Empties the trash from the panel and keeps row state. A leftover count
/// from refused deletions stays visible until the next attempt.
@MainActor
final class TrashEmptyController: ObservableObject {
    @Published private(set) var isEmptying = false
    @Published private(set) var unemptiedCount: Int?

    /// Deletion runs detached so a large or busy trash never stalls the
    /// panel; `onFinished` lets the caller refresh the snapshot count.
    func empty(onFinished: @escaping @MainActor @Sendable () -> Void) {
        guard !isEmptying else { return }
        isEmptying = true
        unemptiedCount = nil
        Task.detached {
            let report = SystemTrashInfo.empty()
            await MainActor.run { [weak self] in
                guard let self else { return }
                isEmptying = false
                unemptiedCount = report.failed > 0 ? report.failed : nil
                onFinished()
            }
        }
    }
}
