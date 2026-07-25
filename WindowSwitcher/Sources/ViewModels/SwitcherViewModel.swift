import SwiftUI
import Combine
import AppSwitcherKit

/// Represents a switcher item — an open window, an installed app, or an app group
enum SwitcherItem: Identifiable, Equatable, Hashable {
    case window(WindowInfo)
    case app(bundleID: String, name: String, icon: NSImage?, path: String?)
    case group(AppGroup, icons: [NSImage])

    var id: String {
        switch self {
        case .window(let w): return "window-\(w.id)"
        case .app(let bid, _, _, _): return "app-\(bid)"
        case .group(let g, _): return "group-\(g.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .window(let w): return w.appName
        case .app(_, let name, _, _): return name
        case .group(let g, _): return g.name
        }
    }

    var subtitle: String? {
        switch self {
        case .window(let w): return w.title.isEmpty ? nil : w.title
        case .app(_, _, _, _): return nil
        case .group(let g, _): return L10n.groupMembers(g.bundleIDs.count)
        }
    }

    var icon: NSImage? {
        switch self {
        case .window(let w): return w.appIcon
        case .app(_, _, let icon, _): return icon
        case .group: return nil // rendered as a composite stack in the view
        }
    }

    /// Member icons for group items (used by the composite icon view)
    var groupIcons: [NSImage]? {
        if case .group(_, let icons) = self { return icons }
        return nil
    }

    var isWindow: Bool {
        if case .window = self { return true }
        return false
    }

    static func == (lhs: SwitcherItem, rhs: SwitcherItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
class SwitcherViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedIndex: Int = 0
    @Published var isSearchActive: Bool = false
    @Published private(set) var windows: [WindowInfo] = []

    /// All installed apps (cached across panel opens, refreshed in the background)
    @Published private var installedApps: [InstalledAppItem] = []

    /// Pinned (allowed) bundle IDs from settings
    private var pinnedBundleIDs: Set<String> = []

    /// App groups from settings
    private var appGroups: [AppGroup] = []

    /// Bundle IDs (lowercased) that belong to some group — those apps are
    /// represented by the group only, never as a standalone window/app entry
    private var groupedBundleIDs: Set<String> {
        Set(appGroups.flatMap { $0.bundleIDs }.map { $0.lowercased() })
    }

    private func isGrouped(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return groupedBundleIDs.contains(bundleID.lowercased())
    }

    /// Combined display items:
    /// - When no search: running windows first, then app groups, then pinned
    ///   apps that are NOT running. Apps that belong to a group are deduped out.
    /// - When searching: matching windows, matching apps, then matching groups.
    var displayItems: [SwitcherItem] {
        if searchText.isEmpty {
            // Running windows (excluding grouped apps)
            var items: [SwitcherItem] = windows
                .filter { !isGrouped($0.appBundleID) }
                .map { .window($0) }

            // App groups — always present, treated like independent apps
            items += appGroups.map { group in
                .group(group, icons: group.bundleIDs.compactMap { Self.icon(forBundleID: $0) })
            }

            // Bundle IDs of running windows
            let runningBundleIDs = Set(windows.compactMap { $0.appBundleID })

            // Pinned apps that are NOT running and NOT in a group
            let pinnedNotRunning = installedApps.filter { app in
                pinnedBundleIDs.contains(app.bundleID)
                    && !runningBundleIDs.contains(app.bundleID)
                    && !isGrouped(app.bundleID)
            }
            items += pinnedNotRunning.map { app in
                .app(bundleID: app.bundleID, name: app.name, icon: app.icon, path: app.path)
            }

            return items
        }

        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let queryWords = query.split(separator: " ").map(String.init)

        // 1. Filter matching windows (excluding grouped apps)
        let matchingWindows = windows.filter { window in
            guard !isGrouped(window.appBundleID) else { return false }
            let titleLower = window.title.lowercased()
            let appNameLower = window.appName.lowercased()
            return queryWords.allSatisfy { word in
                titleLower.contains(word) || appNameLower.contains(word)
            }
        }

        // Collect bundle IDs of matching windows to avoid duplicates
        let windowBundleIDs = Set(matchingWindows.compactMap { $0.appBundleID })

        // 2. Filter matching installed apps (exclude those already shown as windows or grouped)
        let matchingApps = installedApps.filter { app in
            guard !windowBundleIDs.contains(app.bundleID), !isGrouped(app.bundleID) else { return false }
            let nameLower = app.name.lowercased()
            return queryWords.allSatisfy { word in
                nameLower.contains(word)
            }
        }

        // 3. Matching groups (by name)
        let matchingGroups = appGroups.filter { group in
            let nameLower = group.name.lowercased()
            return queryWords.allSatisfy { nameLower.contains($0) }
        }

        // Combine: windows first, then apps (limit to 20), then groups
        var items: [SwitcherItem] = matchingWindows.map { .window($0) }
        items += matchingApps.prefix(20).map { app in
            .app(bundleID: app.bundleID, name: app.name, icon: app.icon, path: app.path)
        }
        items += matchingGroups.map { group in
            .group(group, icons: group.bundleIDs.compactMap { Self.icon(forBundleID: $0) })
        }

        return items
    }

    var totalCount: Int { displayItems.count }

    /// Icon lookup for group members (cached — NSWorkspace lookups add up when
    /// rebuilding the list on every panel open)
    private static var groupIconCache: [String: NSImage] = [:]

    private static func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = groupIconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        groupIconCache[bundleID] = icon
        return icon
    }

    var selectedItem: SwitcherItem? {
        let items = displayItems
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    var selectedWindow: WindowInfo? {
        if let item = selectedItem, case .window(let w) = item {
            return w
        }
        return nil
    }

    private let windowService: WindowService
    private let settingsStore: UserDefaultsSwitcherSettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(windowService: WindowService, settingsStore: UserDefaultsSwitcherSettingsStore = UserDefaultsSwitcherSettingsStore()) {
        self.windowService = windowService
        self.settingsStore = settingsStore

        // Load installed apps cache
        loadInstalledApps()

        // Load pinned bundle IDs from settings
        let settings = settingsStore.load()
        self.pinnedBundleIDs = settings.allowedBundleIDs

        // Reset selection when search text actually changes.
        // removeDuplicates + dropFirst prevent the initial ""/refreshWindows()
        // assignments from clobbering the default "previous window" selection.
        $searchText
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }

    func refreshWindows() {
        let settings = settingsStore.load()
        self.pinnedBundleIDs = settings.allowedBundleIDs
        self.appGroups = settings.appGroups
        // Default list: only show windows from pinned apps (when pinned list is non-empty)
        windows = windowService.getAllWindows(allowedBundleIDs: settings.allowedBundleIDs)
        searchText = ""
        isSearchActive = false
        // TabTab behavior: default select the second ENTRY (previous window).
        // Based on displayItems, not windows — grouping filters/appends change count.
        selectedIndex = displayItems.count > 1 ? 1 : 0
    }

    func selectNext() {
        let count = displayItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    func selectPrevious() {
        let count = displayItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    /// Activate an item — switch to the window, activate/launch the app,
    /// or bring up the whole app group
    func activate(_ item: SwitcherItem) {
        switch item {
        case .window(let window):
            windowService.activateWindow(window)
        case .app(let bundleID, _, _, _):
            windowService.activateApp(bundleID: bundleID)
        case .group(let group, _):
            windowService.activateGroup(group)
        }
    }

    /// Activate the currently selected item
    func activateSelectedItem() {
        guard let item = selectedItem else { return }
        activate(item)
    }

    // MARK: - Private

    /// Shared across view model instances so the panel opens without rescanning the disk each time
    private static var cachedInstalledApps: [InstalledAppItem]?
    private static var lastCatalogRefresh: Date = .distantPast
    private static let catalogRefreshInterval: TimeInterval = 300

    /// Warm the shared catalog cache at app launch. Without this, the first
    /// panel open races the background scan and pinned apps whose windows are
    /// minimized or on another Space are missing from the list.
    static func warmInstalledAppsCache() {
        guard cachedInstalledApps == nil else { return }
        lastCatalogRefresh = Date()
        refreshInstalledAppsCache(into: nil)
    }

    private func loadInstalledApps() {
        if let cached = Self.cachedInstalledApps {
            installedApps = cached
        }

        guard Date().timeIntervalSince(Self.lastCatalogRefresh) >= Self.catalogRefreshInterval else {
            return
        }
        Self.lastCatalogRefresh = Date()
        Self.refreshInstalledAppsCache(into: self)
    }

    /// Scanning /Applications and loading icons is slow — runs off the main
    /// thread and publishes into the shared cache (and the given view model)
    private static func refreshInstalledAppsCache(into viewModel: SwitcherViewModel?) {
        Task.detached(priority: .userInitiated) { [weak viewModel] in
            let catalog = InstalledAppCatalog()
            let apps = catalog.fetchInstalledApps().map { app in
                InstalledAppItem(
                    bundleID: app.bundleID,
                    name: app.displayName,
                    icon: NSWorkspace.shared.icon(forFile: app.bundlePath),
                    path: app.bundlePath
                )
            }
            await MainActor.run { [weak viewModel] in
                Self.cachedInstalledApps = apps
                viewModel?.installedApps = apps
            }
        }
    }
}

/// Lightweight struct for cached installed app info
private struct InstalledAppItem {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let path: String?
}
