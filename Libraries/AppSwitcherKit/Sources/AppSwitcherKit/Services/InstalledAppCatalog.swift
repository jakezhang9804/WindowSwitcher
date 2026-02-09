import Foundation

public final class InstalledAppCatalog: AppCatalogProviding {
    private let fileManager: FileManager
    private let searchRoots: [URL]

    public init(
        fileManager: FileManager = .default,
        searchRoots: [URL] = InstalledAppCatalog.defaultSearchRoots
    ) {
        self.fileManager = fileManager
        self.searchRoots = searchRoots
    }

    public static var defaultSearchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public func fetchInstalledApps() -> [InstalledApp] {
        var appsByBundleID: [String: InstalledApp] = [:]

        for root in searchRoots {
            collectApps(at: root, appsByBundleID: &appsByBundleID)
        }

        return appsByBundleID.values.sorted {
            let nameComparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameComparison == .orderedSame {
                return $0.bundleID < $1.bundleID
            }
            return nameComparison == .orderedAscending
        }
    }

    private func collectApps(at root: URL, appsByBundleID: inout [String: InstalledApp]) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        if root.pathExtension.lowercased() == "app" {
            appendAppBundle(at: root, appsByBundleID: &appsByBundleID)
            return
        }

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return
        }

        for case let itemURL as URL in enumerator {
            guard itemURL.pathExtension.lowercased() == "app" else {
                continue
            }

            appendAppBundle(at: itemURL, appsByBundleID: &appsByBundleID)
            enumerator.skipDescendants()
        }
    }

    private func appendAppBundle(at appURL: URL, appsByBundleID: inout [String: InstalledApp]) {
        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return
        }

        if appsByBundleID[bundleID] != nil {
            return
        }

        let displayName = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            appURL.deletingPathExtension().lastPathComponent
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !displayName.isEmpty else {
            return
        }

        appsByBundleID[bundleID] = InstalledApp(
            bundleID: bundleID,
            displayName: displayName,
            bundlePath: appURL.path
        )
    }
}
