import CoreGraphics
import Foundation
import os

/// One macOS desktop (Space): the WindowServer's numeric id plus the
/// stable UUID macOS keeps for it across launches and reboots.
public struct SpaceInfo: Hashable, Sendable {
    public let id: Int64
    public let uuid: String

    public init(id: Int64, uuid: String) {
        self.id = id
        self.uuid = uuid
    }
}

/// Runtime bridge to SkyLight, the WindowServer's private client framework,
/// for Space (desktop) queries and cross-Space window moves — the same
/// route proven by AltTab and Hammerspoon.
///
/// Blinker ships ad-hoc signed without App Store review, so private symbols
/// carry no approval risk. The real cost of a private API is drift across
/// macOS releases, handled here by resolving every symbol through
/// dlopen/dlsym: if anything is missing, `isAvailable` reports false and
/// callers degrade to their frame-only behavior.
public enum SkyLightSpaces {
    private static let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "skylight")
    private static let bridge: Bridge? = Bridge(logger: logger)

    /// True when every required SkyLight symbol resolved at runtime.
    public static var isAvailable: Bool {
        bridge != nil
    }

    // MARK: - Queries

    /// All desktops across all displays, deduplicated by id.
    public static func spaceCatalog() -> [SpaceInfo] {
        guard let bridge, let displays = bridge.copyManagedDisplaySpaces(bridge.connectionID)
        else { return [] }
        return parseSpaceInfos(displays as Array)
    }

    /// Current Space id for each window id; windows whose Space could not
    /// be resolved are omitted.
    public static func spacesForWindows(_ windowIDs: [Int]) -> [Int: Int64] {
        guard let bridge, !windowIDs.isEmpty else { return [:] }
        var result: CFArray?
        let status = bridge.copySpacesForWindows(
            bridge.connectionID, 0, windowIDs as CFArray, &result
        )
        guard status == 0, let spaces = result else {
            logger.debug("CGSCopySpacesForWindows failed (\(status, privacy: .public))")
            return [:]
        }
        return parseWindowSpaces(spaces as Array, windowIDs: windowIDs)
    }

    /// Moves the windows to the Space with the given id. Returns success.
    public static func moveWindows(_ windowIDs: [Int], toSpace spaceID: Int64) -> Bool {
        guard let bridge, !windowIDs.isEmpty else { return false }
        let status = bridge.moveWindowsToSpaces(
            bridge.connectionID,
            windowIDs as CFArray,
            [NSNumber(value: spaceID)] as CFArray
        )
        if status != 0 {
            logger.debug("CGSMoveWindowsToSpaces failed (\(status, privacy: .public))")
            return false
        }
        return true
    }

    // MARK: - Parsing (pure, unit-tested)

    /// Extracts (id, uuid) pairs from `CGSCopyManagedDisplaySpaces` output:
    /// one dictionary per display, each carrying a "Spaces" array. Entries
    /// are filtered one by one so a single malformed space never drops the
    /// whole display.
    static func parseSpaceInfos(_ displays: [Any]) -> [SpaceInfo] {
        var infos: [SpaceInfo] = []
        var seen = Set<Int64>()
        for case let display as [String: Any] in displays {
            guard let spaces = display["Spaces"] as? [Any] else { continue }
            for case let space as [String: Any] in spaces {
                guard
                    let id = spaceNumberValue(space["id"]),
                    let uuid = space["uuid"] as? String,
                    seen.insert(id).inserted
                else { continue }
                infos.append(SpaceInfo(id: id, uuid: uuid))
            }
        }
        return infos
    }

    /// Zips `CGSCopySpacesForWindows` output with the input window ids;
    /// a count mismatch means the format drifted, so nothing is trusted.
    static func parseWindowSpaces(_ values: [Any], windowIDs: [Int]) -> [Int: Int64] {
        guard values.count == windowIDs.count else { return [:] }
        var mapping: [Int: Int64] = [:]
        for (windowID, value) in zip(windowIDs, values) {
            if let id = spaceNumberValue(value) {
                mapping[windowID] = id
            }
        }
        return mapping
    }

    /// Accepts the shapes seen across macOS releases: a plain number, a
    /// dictionary wrapping one under a key, or nothing at all.
    private static func spaceNumberValue(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let dict = value as? [String: Any] {
            for key in ["ManagedSpaceID", "id"] {
                if let number = dict[key] as? NSNumber {
                    return number.int64Value
                }
            }
        }
        return nil
    }
}

// MARK: - Symbol loading

/// dlopen'd SkyLight with its C entry points. Failing to resolve anything
/// yields `nil`, which callers treat as "Space features unavailable".
private final class Bridge {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    let connectionID: Int32
    let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn
    let copySpacesForWindows: CopySpacesForWindowsFn
    let moveWindowsToSpaces: MoveWindowsToSpacesFn

    init?(logger: Logger) {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            logger.notice("SkyLight not loadable; Space features degrade off")
            return nil
        }
        guard
            let main = Self.load(handle, ["CGSMainConnectionID"], MainConnectionIDFn.self),
            let copySpaces = Self.load(
                handle, ["CGSCopyManagedDisplaySpaces"], CopyManagedDisplaySpacesFn.self
            ),
            let copyWindowSpaces = Self.load(
                handle, ["CGSCopySpacesForWindows"], CopySpacesForWindowsFn.self
            ),
            let move = Self.load(
                handle, ["CGSMoveWindowsToSpaces", "CGSMoveWindowsToSpace"],
                MoveWindowsToSpacesFn.self
            )
        else {
            logger.notice("SkyLight symbols missing; Space features degrade off")
            return nil
        }
        connectionID = main()
        copyManagedDisplaySpaces = copySpaces
        copySpacesForWindows = copyWindowSpaces
        moveWindowsToSpaces = move
    }

    private static func load<T>(
        _ handle: UnsafeMutableRawPointer,
        _ names: [String],
        _: T.Type
    ) -> T? {
        for name in names {
            if let pointer = dlsym(handle, name) {
                return unsafeBitCast(pointer, to: T.self)
            }
        }
        return nil
    }
}

private typealias MainConnectionIDFn = @convention(c) () -> Int32
private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> CFArray?
private typealias CopySpacesForWindowsFn =
    @convention(c) (Int32, UInt32, CFArray, UnsafeMutablePointer<CFArray?>) -> UInt32
private typealias MoveWindowsToSpacesFn = @convention(c) (Int32, CFArray, CFArray) -> UInt32
