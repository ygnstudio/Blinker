import AppKit

/// Bounded, shared cache. Missing apps are retried after a short interval.
@MainActor
enum AppIconStore {
    private final class Entry {
        let image: NSImage
        let expires: Date

        init(image: NSImage, lifetime: TimeInterval) {
            self.image = image
            expires = Date().addingTimeInterval(lifetime)
        }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 128
        return cache
    }()

    static func icon(forBundleIdentifier identifier: String, path: String? = nil) -> NSImage {
        let key = (path ?? identifier) as NSString
        if let entry = cache.object(forKey: key), entry.expires > Date() {
            return entry.image
        }
        let resolvedPath = path
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)?.path
        let image = resolvedPath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        cache.setObject(Entry(image: image, lifetime: resolvedPath == nil ? 30 : 300), forKey: key)
        return image
    }
}
