@testable import BlinkerCore
import CoreGraphics
import XCTest

/// Unit tests for the SkyLight bridge's pure parsing logic and the
/// workspace entry's Space-UUID encoding compatibility. The dlopen'd
/// symbols themselves are exercised only on a live system.
final class SkyLightSpacesTests: XCTestCase {
    // MARK: - Space catalog parsing

    func testParseSpaceInfosExtractsAllDisplays() {
        let displays: [Any] = [
            [
                "Display Identifier": "Main",
                "Spaces": [
                    ["id": 1, "uuid": "AAAA-1111"],
                    ["id": 2, "uuid": "BBBB-2222"]
                ],
                "Current Space": ["id": 1, "uuid": "AAAA-1111"]
            ],
            [
                "Display Identifier": "Side",
                "Spaces": [["id": 3, "uuid": "CCCC-3333"]]
            ]
        ]

        let infos = SkyLightSpaces.parseSpaceInfos(displays)

        XCTAssertEqual(infos, [
            SpaceInfo(id: 1, uuid: "AAAA-1111"),
            SpaceInfo(id: 2, uuid: "BBBB-2222"),
            SpaceInfo(id: 3, uuid: "CCCC-3333")
        ])
    }

    func testParseSpaceInfosSkipsMalformedEntries() {
        let displays: [Any] = [
            [
                "Spaces": [
                    ["id": 1],                      // no uuid
                    ["uuid": "BBBB-2222"],          // no id
                    ["id": 2, "uuid": "CCCC-3333"], // valid
                    "not-a-dictionary"
                ]
            ],
            "not-a-display",
            ["Spaces": "not-an-array"]
        ]

        let infos = SkyLightSpaces.parseSpaceInfos(displays)

        XCTAssertEqual(infos, [SpaceInfo(id: 2, uuid: "CCCC-3333")])
    }

    func testParseSpaceInfosDeduplicatesByID() {
        let displays: [Any] = [
            ["Spaces": [["id": 7, "uuid": "AAAA-1111"]]],
            ["Spaces": [["id": 7, "uuid": "BBBB-2222"]]] // same id, other display
        ]

        let infos = SkyLightSpaces.parseSpaceInfos(displays)

        XCTAssertEqual(infos.count, 1)
        XCTAssertEqual(infos.first?.uuid, "AAAA-1111")
    }

    // MARK: - Window → Space parsing

    func testParseWindowSpacesZipsWithWindowIDs() {
        let mapping = SkyLightSpaces.parseWindowSpaces(
            [1, 2],
            windowIDs: [10, 20]
        )

        XCTAssertEqual(mapping, [10: 1, 20: 2])
    }

    func testParseWindowSpacesAcceptsDictionaryWrappers() {
        let mapping = SkyLightSpaces.parseWindowSpaces(
            [["ManagedSpaceID": 7], 3],
            windowIDs: [10, 20]
        )

        XCTAssertEqual(mapping, [10: 7, 20: 3])
    }

    func testParseWindowSpacesRejectsCountMismatch() {
        let mapping = SkyLightSpaces.parseWindowSpaces(
            [1],
            windowIDs: [10, 20]
        )

        XCTAssertTrue(mapping.isEmpty)
    }

    // MARK: - WorkspaceEntry encoding compatibility

    func testWorkspaceEntryDecodesLegacyJSONWithoutSpaceUUID() throws {
        // Encoding a nil spaceUUID omits the key entirely — exactly the
        // shape of pre-Space captures, so this doubles as the legacy-data
        // compatibility check.
        let legacy = WorkspaceEntry(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let data = try JSONEncoder().encode(legacy)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(object["spaceUUID"])

        let decoded = try JSONDecoder().decode(WorkspaceEntry.self, from: data)

        XCTAssertNil(decoded.spaceUUID)
        XCTAssertEqual(decoded.bundleIdentifier, "com.apple.Safari")
    }

    func testWorkspaceEntryRoundTripsSpaceUUID() throws {
        let entry = WorkspaceEntry(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceUUID: "AAAA-1111"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WorkspaceEntry.self, from: data)

        XCTAssertEqual(decoded.spaceUUID, "AAAA-1111")
    }

    func testSavedWorkspaceWithSpaceUUIDsRoundTrips() throws {
        let workspace = SavedWorkspace(name: "写代码", entries: [
            WorkspaceEntry(
                bundleIdentifier: "com.apple.Terminal",
                appName: "Terminal",
                frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                spaceUUID: "BBBB-2222"
            ),
            WorkspaceEntry(
                bundleIdentifier: "com.apple.Finder",
                appName: "Finder",
                frame: CGRect(x: 610, y: 0, width: 500, height: 400)
            )
        ])

        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(SavedWorkspace.self, from: data)

        XCTAssertEqual(decoded.entries[0].spaceUUID, "BBBB-2222")
        XCTAssertNil(decoded.entries[1].spaceUUID)
    }
}
