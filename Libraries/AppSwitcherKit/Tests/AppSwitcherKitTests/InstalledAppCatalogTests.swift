import XCTest
@testable import AppSwitcherKit

final class InstalledAppCatalogTests: XCTestCase {
    func testFetchInstalledAppsDeduplicatesByBundleIDAndIgnoresMissingBundleID() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: root)
        }

        try createAppBundle(
            at: root.appendingPathComponent("Alpha.app", isDirectory: true),
            bundleID: "com.test.alpha",
            displayName: "Alpha"
        )

        try createAppBundle(
            at: root.appendingPathComponent("AlphaDuplicate.app", isDirectory: true),
            bundleID: "com.test.alpha",
            displayName: "Alpha Duplicate"
        )

        try createAppBundle(
            at: root.appendingPathComponent("NoID.app", isDirectory: true),
            bundleID: nil,
            displayName: "No ID"
        )

        let nestedDirectory = root.appendingPathComponent("Utilities", isDirectory: true)
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try createAppBundle(
            at: nestedDirectory.appendingPathComponent("Beta.app", isDirectory: true),
            bundleID: "com.test.beta",
            displayName: "Beta"
        )

        let catalog = InstalledAppCatalog(searchRoots: [root])
        let apps = catalog.fetchInstalledApps()

        XCTAssertEqual(Set(apps.map(\.bundleID)), Set(["com.test.alpha", "com.test.beta"]))
        XCTAssertEqual(apps.count, 2)
    }

    private func createAppBundle(
        at appURL: URL,
        bundleID: String?,
        displayName: String
    ) throws {
        let fileManager = FileManager.default
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleName": displayName,
            "CFBundleExecutable": "DummyExecutable",
            "CFBundlePackageType": "APPL"
        ]

        if let bundleID {
            plist["CFBundleIdentifier"] = bundleID
        }

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
    }
}
