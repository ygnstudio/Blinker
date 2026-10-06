@testable import BlinkerApp
import XCTest

final class SystemStorageInfoTests: XCTestCase {
    private func raw(_ id: String, name: String? = nil, path: String? = nil,
                     internal isInternal: Bool = false, ejectable: Bool = true,
                     total: Int64 = 500_000_000_000,
                     available: Int64 = 200_000_000_000) -> SystemStorageInfo.RawVolume {
        SystemStorageInfo.RawVolume(id: id, name: name ?? id,
                                    path: path ?? "/Volumes/\(id)",
                                    isInternal: isInternal, isEjectable: ejectable,
                                    totalBytes: total, availableBytes: available)
    }

    func testClassifySeparatesBootAndExternalVolumesSortedByName() {
        let boot = raw("boot-uuid", name: "Macintosh HD", path: "/", internal: true,
                       ejectable: false)
        let value = SystemStorageInfo.classify(boot: boot, raws: [
            raw("boot-uuid", name: "Macintosh HD", path: "/", internal: true, ejectable: false),
            raw("usb-1", name: "Photos"),
            raw("dmg-2", name: "Installer"),
        ])
        XCTAssertEqual(value.boot?.name, "Macintosh HD")
        XCTAssertFalse(value.boot?.isEjectable ?? true)
        XCTAssertEqual(value.external.map(\.name), ["Installer", "Photos"])
    }

    func testClassifyDropsInternalZeroCapacityAndDuplicateVolumes() {
        let value = SystemStorageInfo.classify(boot: nil, raws: [
            raw("a", name: "Data", internal: true),
            raw("b", name: "Empty", total: 0),
            raw("c", name: "Stick"),
            raw("c", name: "Stick"),
        ])
        XCTAssertNil(value.boot)
        XCTAssertEqual(value.external.map(\.id), ["c"])
    }

    func testClassifyDropsMountedEntryMatchingBootID() {
        let boot = raw("same-id", name: "HD", path: "/", internal: true, ejectable: false)
        let value = SystemStorageInfo.classify(boot: boot, raws: [
            raw("same-id", name: "HD", path: "/System/Volumes/Data", internal: false),
        ])
        XCTAssertEqual(value.boot?.id, "same-id")
        XCTAssertTrue(value.external.isEmpty)
    }

    func testFormatBytesUsesFinderDecimalUnits() {
        XCTAssertEqual(SystemStorageInfo.formatBytes(0), "0 MB")
        XCTAssertEqual(SystemStorageInfo.formatBytes(999_000_000), "999 MB")
        XCTAssertEqual(SystemStorageInfo.formatBytes(1_500_000_000), "1.5 GB")
        XCTAssertEqual(SystemStorageInfo.formatBytes(82_340_000_000), "82.3 GB")
        XCTAssertEqual(SystemStorageInfo.formatBytes(494_400_000_000), "494 GB")
        XCTAssertEqual(SystemStorageInfo.formatBytes(-5), "0 MB")
    }

    func testUsedFractionClampsToZeroOne() {
        var volume = SystemStorageInfo.Volume(id: "x", name: "x",
                                              url: URL(fileURLWithPath: "/"),
                                              totalBytes: 100, availableBytes: 25,
                                              isEjectable: true)
        XCTAssertEqual(volume.usedFraction, 0.75, accuracy: 0.001)
        volume.availableBytes = 0
        XCTAssertEqual(volume.usedFraction, 1)
        volume.availableBytes = 200
        XCTAssertEqual(volume.usedFraction, 0)
        volume.totalBytes = 0
        XCTAssertEqual(volume.usedFraction, 0)
    }
}
