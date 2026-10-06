import AppKit
import CoreGraphics
import Foundation

/// One switchable display mode, reduced to what the row shows and what the
/// apply step needs to find the mode again.
struct DisplayModeOption: Equatable, Identifiable, Sendable {
    /// Points, as the user recognizes the resolution.
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    /// Zero or sub-1 values mean "not advertised" and stay hidden.
    let refreshRate: Double
    let isHiDPI: Bool
    let isCurrent: Bool

    var id: String {
        "\(width)x\(height)-\(pixelWidth)x\(pixelHeight)-\(refreshRate)"
    }

    /// "2560 × 1440 · HiDPI · 60Hz" — HiDPI and refresh join only when
    /// meaningful, so common rows stay short.
    var title: String {
        var parts = ["\(width) × \(height)"]
        if isHiDPI { parts.append("HiDPI") }
        if refreshRate >= 1 {
            parts.append("\(Int(refreshRate.rounded()))Hz")
        }
        return parts.joined(separator: " · ")
    }
}

/// Mode facts without CoreGraphics, so filtering and ordering test pure.
struct RawDisplayMode: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
}

/// An active display plus its switchable modes.
struct DisplayEntry: Equatable, Identifiable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    let modes: [DisplayModeOption]
}

/// Resolution switching for the quick actions block. Mode enumeration and
/// application are public CoreGraphics and need no grant; a mode the
/// display rejects simply leaves the current mode untouched.
enum SystemDisplayModes {
    /// Duplicates option keeps the low-resolution variants the default
    /// listing omits, so e.g. a non-HiDPI 1440p stays reachable.
    private static let modeListOptions =
        [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary

    /// Drops empties and exact duplicates, marks HiDPI and the current
    /// mode, and orders by pixel area, then refresh, HiDPI first.
    static func makeOptions(from raw: [RawDisplayMode],
                            current: RawDisplayMode?) -> [DisplayModeOption] {
        var seen = Set<String>()
        let options = raw.compactMap { mode -> DisplayModeOption? in
            guard mode.width > 0, mode.height > 0 else { return nil }
            let key = "\(mode.width)x\(mode.height)-\(mode.pixelWidth)x\(mode.pixelHeight)"
                + "-\(mode.refreshRate)"
            guard seen.insert(key).inserted else { return nil }
            return DisplayModeOption(
                width: mode.width, height: mode.height,
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isHiDPI: mode.pixelWidth > mode.width,
                isCurrent: mode == current
            )
        }
        return options.sorted { lhs, rhs in
            if lhs.width * lhs.height != rhs.width * rhs.height {
                return lhs.width * lhs.height > rhs.width * rhs.height
            }
            if lhs.refreshRate != rhs.refreshRate {
                return lhs.refreshRate > rhs.refreshRate
            }
            return lhs.isHiDPI && !rhs.isHiDPI
        }
    }

    /// All active displays with their switchable modes. Mirrored outputs
    /// collapse to the leading display so a mirrored pair never shows two
    /// rows steering the same picture. Names come from NSScreen; a screen
    /// that cannot be matched falls back to its display id.
    static func activeDisplays() -> [DisplayEntry] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(32, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { id in
                DisplayEntry(id: id, name: name(for: id), modes: modes(for: id))
            }
    }

    static func modes(for display: CGDirectDisplayID) -> [DisplayModeOption] {
        guard let all = CGDisplayCopyAllDisplayModes(display, modeListOptions) as? [CGDisplayMode]
        else { return [] }
        let current = CGDisplayCopyDisplayMode(display).map(rawMode)
        return makeOptions(from: all.filter { $0.isUsableForDesktopGUI() }.map(rawMode),
                           current: current)
    }

    /// Applies by re-matching the option against the live mode list — the
    /// option carries no CGDisplayMode, and the list is cheap to re-read.
    static func setMode(_ option: DisplayModeOption, for display: CGDirectDisplayID) -> Bool {
        guard let modes = CGDisplayCopyAllDisplayModes(display, modeListOptions) as? [CGDisplayMode],
              let match = modes.first(where: { rawMode($0) == rawEquivalent(of: option) })
        else { return false }
        return CGDisplaySetDisplayMode(display, match, nil) == .success
    }

    private static func name(for display: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens
        where (screen.deviceDescription[key] as? CGDirectDisplayID) == display {
            return screen.localizedName
        }
        return String(localized: "显示器 \(String(display))")
    }

    private static func rawMode(_ mode: CGDisplayMode) -> RawDisplayMode {
        RawDisplayMode(width: mode.width, height: mode.height,
                       pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                       refreshRate: mode.refreshRate)
    }

    private static func rawEquivalent(of option: DisplayModeOption) -> RawDisplayMode {
        RawDisplayMode(width: option.width, height: option.height,
                       pixelWidth: option.pixelWidth, pixelHeight: option.pixelHeight,
                       refreshRate: option.refreshRate)
    }
}

/// Panel-side state for the resolution rows. Re-reads after every apply so
/// the checkmarks follow the real current mode — including when the
/// display refused and stayed put.
@MainActor
final class DisplayModesController: ObservableObject {
    @Published private(set) var displays: [DisplayEntry]
    @Published private(set) var applyFailed = false

    private let listDisplays: () -> [DisplayEntry]
    private let apply: (DisplayModeOption, DisplayEntry) -> Bool

    init(listDisplays: @escaping () -> [DisplayEntry] = SystemDisplayModes.activeDisplays,
         apply: @escaping (DisplayModeOption, DisplayEntry) -> Bool = {
             SystemDisplayModes.setMode($0, for: $1.id)
         }) {
        self.listDisplays = listDisplays
        self.apply = apply
        displays = listDisplays()
    }

    func refresh() {
        displays = listDisplays()
    }

    func setMode(_ option: DisplayModeOption, for display: DisplayEntry) {
        applyFailed = !apply(option, display)
        refresh()
    }
}
