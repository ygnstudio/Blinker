import Foundation
import os

/// JSON-encodes `value` and stores it under `key` in `defaults`.
///
/// Encoding failures are logged, never swallowed: a silent failure here
/// would drop the user's configuration with no trace.
public func storeEncoded<T: Encodable>(
    _ value: T,
    forKey key: String,
    in defaults: UserDefaults,
    category: String
) {
    do {
        try defaults.set(JSONEncoder().encode(value), forKey: key)
    } catch {
        Logger(subsystem: "com.ygnstudio.blinker", category: category).error(
            "Failed to encode \(String(describing: T.self)) for key \(key, privacy: .public): \(error)"
        )
    }
}

/// Preserves an undecodable blob under `<key>.corrupt-backup` before the
/// caller starts empty. Without this, a corrupt store would decode to an
/// empty list and the very next save would overwrite the blob — silently
/// erasing whatever was recoverable. The backup keeps the latest corrupt
/// state; the logger entry names both keys so support can find it.
public func quarantineCorruptBlob(
    _ data: Data,
    forKey key: String,
    in defaults: UserDefaults,
    category: String
) {
    let backupKey = key + ".corrupt-backup"
    defaults.set(data, forKey: backupKey)
    Logger(subsystem: "com.ygnstudio.blinker", category: category).error(
        "Undecodable data for key \(key, privacy: .public); quarantined as \(backupKey, privacy: .public)"
    )
}
