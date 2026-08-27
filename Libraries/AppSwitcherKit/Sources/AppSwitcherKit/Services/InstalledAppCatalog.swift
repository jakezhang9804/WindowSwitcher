import Foundation
import CoreServices

public final class InstalledAppCatalog: AppCatalogProviding {
    private let fileManager: FileManager
    private let searchRoots: [URL]
    private let excludedBundleIDs: Set<String>
    private let includeMetadataIndex: Bool

    public init(
        fileManager: FileManager = .default,
        searchRoots: [URL]? = nil,
        excludedBundleIDs: Set<String> = [],
        includeMetadataIndex: Bool? = nil
    ) {
        self.fileManager = fileManager
        self.searchRoots = searchRoots ?? InstalledAppCatalog.defaultSearchRoots
        self.excludedBundleIDs = Set(excludedBundleIDs.map { $0.lowercased() })
        self.includeMetadataIndex = includeMetadataIndex ?? (searchRoots == nil)
    }

    /// Standard user-facing application locations. Direct children are inspected
    /// separately so symlinked system apps such as Safari are not skipped by
    /// `FileManager.DirectoryEnumerator`.
    public static var defaultSearchRoots: [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true)
        ]

        // Include conventional application folders on mounted external volumes.
        let volumeKeys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsBrowsableKey]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: volumeKeys,
            options: [.skipHiddenVolumes]
        ) ?? []
        for volume in volumes where volume.path != "/" {
            roots.append(volume.appendingPathComponent("Applications", isDirectory: true))
            let topLevelApps = (try? FileManager.default.contentsOfDirectory(
                at: volume,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            roots.append(contentsOf: topLevelApps.filter { $0.pathExtension.lowercased() == "app" })
        }

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    public func fetchInstalledApps() -> [InstalledApp] {
        var appsByBundleID: [String: InstalledApp] = [:]

        for root in searchRoots {
            collectApps(at: root, appsByBundleID: &appsByBundleID)
        }
        if includeMetadataIndex {
            for appURL in metadataIndexedApplicationURLs() {
                appendAppBundle(at: appURL, appsByBundleID: &appsByBundleID)
            }
        }

        return appsByBundleID.values.sorted {
            if $0.isBackgroundOnly != $1.isBackgroundOnly {
                return !$0.isBackgroundOnly
            }
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

        // DirectoryEnumerator does not consistently yield symlinks to packages.
        // Inspect direct children first so `/Applications/Safari.app` is found.
        if let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where child.pathExtension.lowercased() == "app" {
                appendAppBundle(at: child, appsByBundleID: &appsByBundleID)
            }
        }

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return
        }

        for case let itemURL as URL in enumerator {
            let values = try? itemURL.resourceValues(forKeys: resourceKeys)
            let isApp = itemURL.pathExtension.lowercased() == "app"

            if isApp {
                appendAppBundle(at: itemURL, appsByBundleID: &appsByBundleID)
                enumerator.skipDescendants()
                continue
            }

            // Never surface helper apps nested inside non-app packages such as
            // installers, frameworks, plug-ins, or bundles.
            if values?.isPackage == true {
                enumerator.skipDescendants()
            }
        }
    }

    private func metadataIndexedApplicationURLs() -> [URL] {
        let expression = "kMDItemContentType == 'com.apple.application-bundle'" as CFString
        guard let query = MDQueryCreate(kCFAllocatorDefault, expression, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeComputer] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }

        var urls: [URL] = []
        urls.reserveCapacity(MDQueryGetResultCount(query))
        for index in 0..<MDQueryGetResultCount(query) {
            let item = unsafeBitCast(MDQueryGetResultAtIndex(query, index), to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  path.hasSuffix(".app"),
                  isUserFacingMetadataPath(path) else {
                continue
            }
            urls.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        return urls
    }

    private func isUserFacingMetadataPath(_ path: String) -> Bool {
        // Nested app bundles are helper processes owned by the containing app.
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.dropLast().allSatisfy({ !$0.lowercased().hasSuffix(".app") }) else {
            return false
        }

        if path.hasPrefix("/System/Library/") {
            return path == "/System/Library/CoreServices/Finder.app"
                || path.hasPrefix("/System/Library/CoreServices/Applications/")
        }
        if path.hasPrefix("/Library/") { return false }
        if path.contains("/Library/Application Support/")
            || path.contains("/Library/Developer/")
            || path.contains("/Library/Caches/") {
            return false
        }
        return true
    }

    private func appendAppBundle(at appURL: URL, appsByBundleID: inout [String: InstalledApp]) {
        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty,
              !excludedBundleIDs.contains(bundleID.lowercased()) else {
            return
        }

        let displayName = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            appURL.deletingPathExtension().lastPathComponent
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }

        let bundleFileName = appURL.deletingPathExtension().lastPathComponent
        let executableName = (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var aliases = [bundleFileName, executableName].compactMap { $0 }
        aliases.append(contentsOf: localizedDisplayNameAliases(in: bundle))
        aliases.removeAll { $0.isEmpty || $0.caseInsensitiveCompare(displayName) == .orderedSame }
        var seenAliases = Set<String>()
        aliases = aliases.filter { seenAliases.insert($0.lowercased()).inserted }

        let app = InstalledApp(
            bundleID: bundleID,
            displayName: displayName,
            bundlePath: appURL.path,
            isBackgroundOnly: booleanInfoValue("LSUIElement", in: bundle)
                || booleanInfoValue("LSBackgroundOnly", in: bundle),
            searchAliases: aliases
        )

        let key = bundleID.lowercased()
        if let existing = appsByBundleID[key] {
            if shouldPrefer(app, over: existing) {
                appsByBundleID[key] = app
            }
        } else {
            appsByBundleID[key] = app
        }
    }

    private func booleanInfoValue(_ key: String, in bundle: Bundle) -> Bool {
        if let value = bundle.object(forInfoDictionaryKey: key) as? Bool { return value }
        if let value = bundle.object(forInfoDictionaryKey: key) as? NSNumber { return value.boolValue }
        return false
    }

    private func localizedDisplayNameAliases(in bundle: Bundle) -> [String] {
        var localizations = Set(bundle.localizations)
        if let resourcesURL = bundle.resourceURL,
           let children = try? fileManager.contentsOfDirectory(
               at: resourcesURL,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            for child in children where child.pathExtension.lowercased() == "lproj" {
                localizations.insert(child.deletingPathExtension().lastPathComponent)
            }
        }

        return localizations.compactMap { localization -> String? in
            var infoURL: URL?
            if let resourcesURL = bundle.resourceURL {
                let directURL = resourcesURL
                    .appendingPathComponent("\(localization).lproj", isDirectory: true)
                    .appendingPathComponent("InfoPlist.strings")
                if fileManager.fileExists(atPath: directURL.path) { infoURL = directURL }
            }
            if infoURL == nil {
                infoURL = bundle.url(
                    forResource: "InfoPlist",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: localization
                )
            }
            guard let url = infoURL,
            let data = try? Data(contentsOf: url),
            let dictionary = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: String] else {
                return nil
            }
            return dictionary["CFBundleDisplayName"] ?? dictionary["CFBundleName"]
        }
    }

    private func shouldPrefer(_ candidate: InstalledApp, over existing: InstalledApp) -> Bool {
        if existing.isBackgroundOnly != candidate.isBackgroundOnly {
            return !candidate.isBackgroundOnly
        }

        func locationRank(_ path: String) -> Int {
            if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/") { return 0 }
            if path.hasPrefix("/Applications/") { return 1 }
            if path.hasPrefix("/System/Applications/") { return 2 }
            return 3
        }
        return locationRank(candidate.bundlePath) < locationRank(existing.bundlePath)
    }
}
