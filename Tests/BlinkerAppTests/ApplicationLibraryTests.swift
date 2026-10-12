@testable import BlinkerApp
import Darwin
import Foundation
import XCTest

final class ApplicationLibraryTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blinker.ApplicationLibraryTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeApplication(at url: URL, identifier: String, name: String? = nil,
                                 displayName: String? = nil) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"]
        info["CFBundleName"] = name
        info["CFBundleDisplayName"] = displayName
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    func testApplicationReadsBundleMetadataAndUsesDisplayNameBeforeBundleName() throws {
        let root = try makeDirectory()
        let url = root.appendingPathComponent("OnDiskName.app", isDirectory: true)
        try makeApplication(at: url, identifier: "fixture.discovery.metadata", name: "Bundle Name",
                            displayName: "Display Name")

        let app = try XCTUnwrap(ApplicationLibrary.application(at: url))
        XCTAssertEqual(app.id, "fixture.discovery.metadata")
        XCTAssertEqual(app.name, "Display Name")
        XCTAssertEqual(app.path, url.resolvingSymlinksInPath().path)
    }

    func testApplicationNameFallsBackToBundleNameThenResolvedFilename() throws {
        let root = try makeDirectory()
        let named = root.appendingPathComponent("Named.app", isDirectory: true)
        let unnamed = root.appendingPathComponent("Unnamed.app", isDirectory: true)
        try makeApplication(at: named, identifier: "fixture.discovery.named", name: "Bundle Name")
        try makeApplication(at: unnamed, identifier: "fixture.discovery.unnamed")

        XCTAssertEqual(ApplicationLibrary.application(at: named)?.name, "Bundle Name")
        XCTAssertEqual(ApplicationLibrary.application(at: unnamed)?.name, "Unnamed")
    }

    func testRelativeApplicationLinkResolvesThroughALinkedParentDirectory() throws {
        let root = try makeDirectory()
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let cryptexes = root.appendingPathComponent("System/Cryptexes", isDirectory: true)
        let target = root.appendingPathComponent("Payloads/Current/System/Applications/Browser.app",
                                               isDirectory: true)
        try makeApplication(at: target, identifier: "fixture.discovery.linked", name: "Browser")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cryptexes, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: cryptexes.appendingPathComponent("App").path,
                                                  withDestinationPath: "../../Payloads/Current")
        let link = applications.appendingPathComponent("Browser.app")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "../System/Cryptexes/App/System/Applications/Browser.app"
        )

        let app = try XCTUnwrap(ApplicationLibrary.application(at: link))
        XCTAssertEqual(app.id, "fixture.discovery.linked")
        XCTAssertEqual(app.name, "Browser")
        XCTAssertEqual(app.path, target.resolvingSymlinksInPath().path)
        XCTAssertEqual(app, ApplicationLibrary.application(at: target))
    }

    func testDiscoveryIncludesFinderHiddenApplicationLinksAndOrdinaryApplications() throws {
        let root = try makeDirectory()
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let target = root.appendingPathComponent("Payload/Browser.app", isDirectory: true)
        let ordinary = applications.appendingPathComponent("Editor.app", isDirectory: true)
        try makeApplication(at: target, identifier: "fixture.discovery.hidden-link", name: "Browser")
        try makeApplication(at: ordinary, identifier: "fixture.discovery.ordinary", name: "Editor")
        let link = applications.appendingPathComponent("Browser.app")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                  withDestinationPath: "../Payload/Browser.app")
        XCTAssertEqual(lchflags(link.path, UInt32(UF_HIDDEN)), 0,
                       "The fixture must reproduce Safari's hidden symlink flag")
        let visible = try FileManager.default.contentsOfDirectory(
            at: applications, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        XCTAssertFalse(visible.contains { $0.lastPathComponent == "Browser.app" })

        let apps = ApplicationLibrary.installedApps(in: [applications])
        XCTAssertEqual(Set(apps.map(\.id)),
                       Set(["fixture.discovery.hidden-link", "fixture.discovery.ordinary"]))
        XCTAssertEqual(apps.first { $0.id == "fixture.discovery.hidden-link" }?.path,
                       target.resolvingSymlinksInPath().path)
    }

    func testDiscoveryDeduplicatesALinkAndItsTargetWithoutRecursingOrIncludingDotEntries() throws {
        let root = try makeDirectory()
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        let target = payload.appendingPathComponent("Browser.app", isDirectory: true)
        try makeApplication(at: target, identifier: "fixture.discovery.duplicate", name: "Browser")
        try makeApplication(at: applications.appendingPathComponent(".Private.app"),
                            identifier: "fixture.discovery.dot")
        try makeApplication(at: applications.appendingPathComponent("Nested/Inner.app"),
                            identifier: "fixture.discovery.nested")
        let alias = applications.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(atPath: alias.path,
                                                  withDestinationPath: "../Payload/Browser.app")

        let apps = ApplicationLibrary.installedApps(in: [applications, payload])
        XCTAssertEqual(apps.map(\.id), ["fixture.discovery.duplicate"])
        XCTAssertEqual(apps.first?.path, target.resolvingSymlinksInPath().path)
    }

    func testDiscoverySkipsBrokenLinksInvalidBundlesAndUnavailableDirectories() throws {
        let root = try makeDirectory()
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let valid = applications.appendingPathComponent("Valid.app", isDirectory: true)
        try makeApplication(at: valid, identifier: "fixture.discovery.valid", name: "Valid")
        let invalid = applications.appendingPathComponent("Invalid.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        let missing = applications.appendingPathComponent("Missing.app")
        try FileManager.default.createSymbolicLink(atPath: missing.path,
                                                  withDestinationPath: "../Missing.app")
        let nonApplication = applications.appendingPathComponent("Document.bundle", isDirectory: true)
        try makeApplication(at: nonApplication, identifier: "fixture.discovery.not-app")

        let unavailable = root.appendingPathComponent("Unavailable")
        let apps = ApplicationLibrary.installedApps(in: [unavailable, applications])
        XCTAssertEqual(apps.map(\.id), ["fixture.discovery.valid"])
        XCTAssertNil(ApplicationLibrary.application(at: nonApplication))
    }
}
