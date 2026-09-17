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
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    } catch {
        Logger(subsystem: "com.ygnstudio.blinker", category: category).error(
            "Failed to encode \(String(describing: T.self)) for key \(key, privacy: .public): \(error)"
        )
    }
}
