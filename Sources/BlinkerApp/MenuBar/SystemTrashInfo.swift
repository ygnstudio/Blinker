import AppKit
import Foundation

/// Trash support for the quick actions block. Two paths, two grants:
/// the item count is a plain `FileManager` listing, which needs Full Disk
/// Access to see `~/.Trash` — without it the read fails silently and the
/// row simply hides the count. Emptying goes through the Finder via Apple
/// Events, which asks for Automation consent once and needs nothing else;
/// the Finder itself has the access to empty every volume's trash.
enum SystemTrashInfo {
    /// The current user's trash on the boot volume (`~/.Trash` unsandboxed).
    static let trashURL = FileManager.default
        .urls(for: .trashDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")

    /// Top-level entries, hidden files included. nil when the listing is
    /// refused (no Full Disk Access) so the UI never mistakes a denied
    /// read for an empty trash.
    static func itemCount(at url: URL = trashURL) -> Int? {
        let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)
        return items?.count
    }

    /// The Finder owns the semantics: every volume, locked-item handling
    /// and in-use reporting identical to Empty Trash in its menu.
    static let emptyTrashScript = "tell application \"Finder\" to empty trash"

    enum EmptyFailure: Equatable, Sendable {
        /// errAEEventNotPermitted — the user declined (or has not yet been
        /// asked) the Finder Automation consent.
        case automationDenied
        /// The script ran but the Finder reported an error, e.g. items in
        /// use; the system-localized message is shown as is.
        case failed(String)
    }

    /// Maps `executeAndReturnError` output. A nil dictionary means success;
    /// callers pass it through only when the execution failed.
    static func failure(from errorInfo: [AnyHashable: Any]?) -> EmptyFailure? {
        guard let errorInfo else { return nil }
        if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
            return .automationDenied
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
        return .failed(message ?? String(localized: "清空回收站失败"))
    }
}

/// Empties the trash from the panel and keeps row state. The failure, when
/// any, stays visible until the next attempt.
@MainActor
final class TrashEmptyController: ObservableObject {
    @Published private(set) var isEmptying = false
    @Published private(set) var failure: SystemTrashInfo.EmptyFailure?

    /// Apple Events run detached so a large trash never stalls the panel;
    /// `onFinished` lets the caller refresh the snapshot count.
    func empty(onFinished: @escaping @MainActor @Sendable () -> Void) {
        guard !isEmptying else { return }
        isEmptying = true
        failure = nil
        Task.detached {
            var errorInfo: NSDictionary?
            let script = NSAppleScript(source: SystemTrashInfo.emptyTrashScript)
            script?.executeAndReturnError(&errorInfo)
            let outcome = SystemTrashInfo.failure(from: errorInfo as? [AnyHashable: Any])
            await MainActor.run { [weak self] in
                guard let self else { return }
                isEmptying = false
                failure = outcome
                onFinished()
            }
        }
    }
}
