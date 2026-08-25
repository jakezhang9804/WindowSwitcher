import Foundation
import Testing
@testable import AppSwitcherKit

@Suite("Installed app catalog")
struct InstalledAppCatalogTests {
    @Test("Catalog deduplicates bundle identifiers and skips invalid app bundles")
    func fetchInstalledAppsDeduplicatesByBundleIDAndIgnoresMissingBundleID() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

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

        let apps = InstalledAppCatalog(searchRoots: [root]).fetchInstalledApps()

        #expect(Set(apps.map(\.bundleID)) == Set(["com.test.alpha", "com.test.beta"]))
        #expect(apps.map(\.displayName) == ["Alpha", "Beta"])
    }

    private func createAppBundle(
        at appURL: URL,
        bundleID: String?,
        displayName: String
    ) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleName": displayName,
            "CFBundleExecutable": "DummyExecutable",
            "CFBundlePackageType": "APPL"
        ]
        if let bundleID { plist["CFBundleIdentifier"] = bundleID }

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
    }
}
