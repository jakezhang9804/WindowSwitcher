import Foundation
import Testing
@testable import AppSwitcherKit

@Suite("Installed app catalog")
struct InstalledAppCatalogTests {
    @Test("Catalog deduplicates bundle identifiers and skips invalid app bundles")
    func fetchInstalledAppsDeduplicatesByBundleIDAndIgnoresMissingBundleID() throws {
        try withTemporaryRoot { root in
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

            let nested = root.appendingPathComponent("Utilities", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try createAppBundle(
                at: nested.appendingPathComponent("Beta.app", isDirectory: true),
                bundleID: "com.test.beta",
                displayName: "Beta"
            )

            let apps = InstalledAppCatalog(searchRoots: [root]).fetchInstalledApps()
            #expect(Set(apps.map(\.bundleID)) == Set(["com.test.alpha", "com.test.beta"]))
            #expect(apps.map(\.displayName) == ["Alpha", "Beta"])
        }
    }

    @Test("Catalog excludes the current application bundle ID")
    func excludesBundleIDs() throws {
        try withTemporaryRoot { root in
            try createAppBundle(at: root.appendingPathComponent("WindowSwitcher.app"), bundleID: "com.test.self", displayName: "WindowSwitcher")
            try createAppBundle(at: root.appendingPathComponent("Other.app"), bundleID: "com.test.other", displayName: "Other")

            let apps = InstalledAppCatalog(searchRoots: [root], excludedBundleIDs: ["COM.TEST.SELF"]).fetchInstalledApps()
            #expect(apps.map(\.bundleID) == ["com.test.other"])
        }
    }

    @Test("Direct app symlinks are discovered")
    func discoversSymlinkedApps() throws {
        try withTemporaryRoot { root in
            let storage = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: storage) }

            let target = storage.appendingPathComponent("Safari.app", isDirectory: true)
            try createAppBundle(at: target, bundleID: "com.test.safari", displayName: "Safari")
            let link = root.appendingPathComponent("Safari.app", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let apps = InstalledAppCatalog(searchRoots: [root]).fetchInstalledApps()
            #expect(apps.map(\.bundleID) == ["com.test.safari"])
            let recordedTarget = apps.first.map { URL(fileURLWithPath: $0.bundlePath).resolvingSymlinksInPath().path }
            #expect(recordedTarget == target.resolvingSymlinksInPath().path)
        }
    }

    @Test("Background utilities are labeled and nested package helpers are skipped")
    func labelsUtilitiesAndSkipsHelpers() throws {
        try withTemporaryRoot { root in
            try createAppBundle(
                at: root.appendingPathComponent("MenuTool.app"),
                bundleID: "com.test.menu",
                displayName: "Menu Tool",
                extraInfo: ["LSUIElement": true]
            )
            try createInfoPlist(
                at: root.appendingPathComponent("MenuTool.app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"),
                values: ["CFBundleDisplayName": "菜单工具"]
            )

            let package = root.appendingPathComponent("Driver.bundle", isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try createInfoPlist(
                at: package.appendingPathComponent("Contents/Info.plist"),
                values: ["CFBundleIdentifier": "com.test.driver", "CFBundlePackageType": "BNDL"]
            )
            try createAppBundle(
                at: package.appendingPathComponent("Helper.app"),
                bundleID: "com.test.helper",
                displayName: "Internal Helper"
            )

            let apps = InstalledAppCatalog(searchRoots: [root]).fetchInstalledApps()
            #expect(apps.count == 1)
            #expect(apps.first?.bundleID == "com.test.menu")
            #expect(apps.first?.isBackgroundOnly == true)
            #expect(apps.first?.searchAliases.contains("MenuTool") == true)
            #expect(apps.first?.searchAliases.contains("DummyExecutable") == true)
            #expect(apps.first?.searchAliases.contains("菜单工具") == true)
        }
    }

    @Test("Legacy InstalledApp JSON defaults the background flag to false")
    func legacyInstalledAppDecoding() throws {
        let data = Data(#"{"bundleID":"com.test.app","displayName":"App","bundlePath":"/Applications/App.app"}"#.utf8)
        let app = try JSONDecoder().decode(InstalledApp.self, from: data)
        #expect(app.isBackgroundOnly == false)
        #expect(app.searchAliases.isEmpty)
    }

    private func withTemporaryRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func createAppBundle(
        at appURL: URL,
        bundleID: String?,
        displayName: String,
        extraInfo: [String: Any] = [:]
    ) throws {
        var values: [String: Any] = [
            "CFBundleName": displayName,
            "CFBundleExecutable": "DummyExecutable",
            "CFBundlePackageType": "APPL",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en", "zh-Hans"]
        ]
        if let bundleID { values["CFBundleIdentifier"] = bundleID }
        for (key, value) in extraInfo { values[key] = value }
        try createInfoPlist(at: appURL.appendingPathComponent("Contents/Info.plist"), values: values)
    }

    private func createInfoPlist(at url: URL, values: [String: Any]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: url)
    }
}
