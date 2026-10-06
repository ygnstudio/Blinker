import AppKit
import Foundation

/// Mounted-volume listing for the status panel's storage block, plus eject.
/// Everything is local `FileManager`/`NSWorkspace` API — no permission, no
/// subprocess. Capacity uses the same 10⁹-byte gigabytes the Finder shows.
enum SystemStorageInfo {
    struct Volume: Equatable, Sendable, Identifiable {
        /// Volume UUID, falling back to the mount path when none exists.
        var id: String
        var name: String
        var url: URL
        var totalBytes: Int64
        var availableBytes: Int64
        /// External volumes are assumed ejectable unless the system says so;
        /// a failed attempt surfaces inline instead of hiding the button.
        var isEjectable: Bool

        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return min(1, max(0, 1 - Double(availableBytes) / Double(totalBytes)))
        }
    }

    struct Value: Equatable, Sendable {
        var boot: Volume?
        var external: [Volume]
    }

    /// What the resource-values read actually returns; the pure classification
    /// below is what tests exercise.
    struct RawVolume: Equatable, Sendable {
        var id: String
        var name: String
        var path: String
        var isInternal: Bool
        var isEjectable: Bool
        var totalBytes: Int64
        var availableBytes: Int64
    }

    private static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey,
        .volumeIsEjectableKey,
        .volumeIsRemovableKey,
        .volumeUUIDStringKey,
    ]

    static func read() -> Value {
        let keys = Set(resourceKeys)
        let boot = rawVolume(at: URL(fileURLWithPath: "/"), keys: keys)
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []
        let raws = mounted.compactMap { rawVolume(at: $0, keys: keys) }
        return classify(boot: boot, raws: raws)
    }

    /// The boot volume is authoritative on its own; the mounted list only
    /// contributes non-internal, positive-capacity volumes, deduplicated by
    /// id and sorted by name for a stable panel order.
    static func classify(boot: RawVolume?, raws: [RawVolume]) -> Value {
        var seen = Set<String>()
        let external = raws
            .filter { !$0.isInternal && $0.totalBytes > 0 && $0.id != boot?.id }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(Self.volume(from:))
        return Value(boot: boot.map(Self.volume(from:)), external: external)
    }

    private static func volume(from raw: RawVolume) -> Volume {
        Volume(id: raw.id, name: raw.name, url: URL(fileURLWithPath: raw.path),
               totalBytes: raw.totalBytes, availableBytes: raw.availableBytes,
               isEjectable: raw.isEjectable)
    }

    private static func rawVolume(at url: URL, keys: Set<URLResourceKey>) -> RawVolume? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isInternal = values.volumeIsInternal ?? (url.path == "/")
        let total = Int64(values.volumeTotalCapacity ?? 0)
        // Important-usage capacity matches the Finder's "available" figure;
        // fall back to the plain free count when the volume cannot report it.
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0
        let ejectable = values.volumeIsEjectable ?? values.volumeIsRemovable ?? !isInternal
        return RawVolume(
            id: values.volumeUUIDString ?? url.path,
            name: values.volumeName ?? url.lastPathComponent,
            path: url.path,
            isInternal: isInternal,
            isEjectable: ejectable,
            totalBytes: total,
            availableBytes: max(0, available)
        )
    }

    /// `182.4 GB`-style readout in decimal (Finder) units; whole numbers
    /// above 100 GB, megabytes below 1 GB.
    static func formatBytes(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        let gigabyte = 1_000_000_000.0
        let megabyte = 1_000_000.0
        if value >= gigabyte {
            let scaled = value / gigabyte
            return scaled >= 100
                ? String(format: "%.0f GB", scaled)
                : String(format: "%.1f GB", scaled)
        }
        return String(format: "%.0f MB", value / megabyte)
    }
}

/// Ejects volumes from the panel and keeps per-volume state for the rows.
/// Errors stay visible until the volume disappears or another attempt runs.
@MainActor
final class VolumeEjectController: ObservableObject {
    @Published private(set) var ejectingIDs: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    /// The only remaining SDK entry point is synchronous (macOS 27 headers
    /// dropped the completion-handler variant), so the call runs detached:
    /// a busy or spun-down disk must not stall the panel.
    func eject(_ volume: SystemStorageInfo.Volume) {
        guard !ejectingIDs.contains(volume.id) else { return }
        ejectingIDs.insert(volume.id)
        errors[volume.id] = nil
        Task.detached { [weak self] in
            let outcome = Result { try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                ejectingIDs.remove(volume.id)
                if case let .failure(error) = outcome {
                    errors[volume.id] = error.localizedDescription
                }
            }
        }
    }

    /// Drops state for volumes the latest snapshot no longer lists, so a
    /// successful eject (or an unplugged drive) never leaves a stale error.
    func prune(keeping volumes: [SystemStorageInfo.Volume]) {
        let alive = Set(volumes.map(\.id))
        ejectingIDs.formIntersection(alive)
        errors = errors.filter { alive.contains($0.key) }
    }
}
