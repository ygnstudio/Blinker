import AppKit

/// Resolves and caches app icons by bundle identifier. `NSWorkspace` icon
/// resolution hits the disk (bundle lookup + icns read), so list rows must
/// never compute it inline — every render would pay the cost.
enum AppIconStore {
    private static let cache = NSCache<NSString, NSImage>()

    /// The app's icon, falling back to the generic application icon when
    /// the app is no longer installed. The fallback is deliberately *not*
    /// cached: if the app gets installed later, the next lookup resolves
    /// the real icon within the same session instead of showing the
    /// placeholder until relaunch.
    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let cached = cache.object(forKey: bundleIdentifier as NSString) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let resolved = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(resolved, forKey: bundleIdentifier as NSString)
        return resolved
    }
}
