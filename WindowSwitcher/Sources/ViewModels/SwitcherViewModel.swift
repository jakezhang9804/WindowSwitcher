import SwiftUI
import Combine
import AppSwitcherKit

/// Represents a search result item — either an open window or an installed app
enum SwitcherItem: Identifiable, Equatable, Hashable {
    case window(WindowInfo)
    case app(bundleID: String, name: String, icon: NSImage?, path: String?)

    var id: String {
        switch self {
        case .window(let w): return "window-\(w.id)"
        case .app(let bid, _, _, _): return "app-\(bid)"
        }
    }

    var displayName: String {
        switch self {
        case .window(let w): return w.appName
        case .app(_, let name, _, _): return name
        }
    }

    var subtitle: String? {
        switch self {
        case .window(let w): return w.title.isEmpty ? nil : w.title
        case .app(_, _, _, _): return nil
        }
    }

    var icon: NSImage? {
        switch self {
        case .window(let w): return w.appIcon
        case .app(_, _, let icon, _): return icon
        }
    }

    var isWindow: Bool {
        if case .window = self { return true }
        return false
    }

    /// Whether this is a pinned app (not a running window)
    var isPinnedApp: Bool {
        if case .app = self { return true }
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

    /// All installed apps (loaded once, cached)
    private var installedApps: [InstalledAppItem] = []

    /// Pinned (allowed) bundle IDs from settings
    private var pinnedBundleIDs: Set<String> = []

    /// Combined display items:
    /// - When no search: running windows first, then pinned apps that are NOT running
    /// - When searching: matching windows first, then matching installed apps
    var displayItems: [SwitcherItem] {
        if searchText.isEmpty {
            // Running windows
            var items: [SwitcherItem] = windows.map { .window($0) }

            // Bundle IDs of running windows
            let runningBundleIDs = Set(windows.compactMap { $0.appBundleID })

            // Pinned apps that are NOT currently running — show them at the bottom
            let pinnedNotRunning = installedApps.filter { app in
                pinnedBundleIDs.contains(app.bundleID) && !runningBundleIDs.contains(app.bundleID)
            }
            items += pinnedNotRunning.map { app in
                .app(bundleID: app.bundleID, name: app.name, icon: app.icon, path: app.path)
            }

            return items
        }

        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let queryWords = query.split(separator: " ").map(String.init)

        // 1. Filter matching windows
        let matchingWindows = windows.filter { window in
            let titleLower = window.title.lowercased()
            let appNameLower = window.appName.lowercased()
            return queryWords.allSatisfy { word in
                titleLower.contains(word) || appNameLower.contains(word)
            }
        }

        // Collect bundle IDs of matching windows to avoid duplicates
        let windowBundleIDs = Set(matchingWindows.compactMap { $0.appBundleID })

        // 2. Filter matching installed apps (exclude those already shown as windows)
        let matchingApps = installedApps.filter { app in
            guard !windowBundleIDs.contains(app.bundleID) else { return false }
            let nameLower = app.name.lowercased()
            return queryWords.allSatisfy { word in
                nameLower.contains(word)
            }
        }

        // Combine: windows first, then apps (limit to 20 app results)
        var items: [SwitcherItem] = matchingWindows.map { .window($0) }
        items += matchingApps.prefix(20).map { app in
            .app(bundleID: app.bundleID, name: app.name, icon: app.icon, path: app.path)
        }

        return items
    }

    /// For backward compatibility — filtered windows only
    var filteredWindows: [WindowInfo] {
        if searchText.isEmpty { return windows }
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let queryWords = query.split(separator: " ").map(String.init)
        return windows.filter { window in
            let titleLower = window.title.lowercased()
            let appNameLower = window.appName.lowercased()
            return queryWords.allSatisfy { word in
                titleLower.contains(word) || appNameLower.contains(word)
            }
        }
    }

    var totalCount: Int { windows.count }

    /// Whether there are pinned apps that are not running (for section header display)
    var hasPinnedNotRunning: Bool {
        let runningBundleIDs = Set(windows.compactMap { $0.appBundleID })
        return pinnedBundleIDs.contains(where: { !runningBundleIDs.contains($0) })
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

        // Reset selection when search text changes
        $searchText
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }

    func refreshWindows() {
        let settings = settingsStore.load()
        self.pinnedBundleIDs = settings.allowedBundleIDs
        // Default list: only show windows from pinned apps (when pinned list is non-empty)
        windows = windowService.getAllWindows(allowedBundleIDs: settings.allowedBundleIDs)
        // TabTab behavior: default select the second item (previous window)
        selectedIndex = windows.count > 1 ? 1 : 0
        searchText = ""
        isSearchActive = false
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

    func activateWindow(_ window: WindowInfo) {
        windowService.activateWindow(window)
    }

    /// Activate the selected item — either switch to window or launch app
    func activateSelectedItem() {
        guard let item = selectedItem else { return }
        switch item {
        case .window(let window):
            windowService.activateWindow(window)
        case .app(let bundleID, _, _, _):
            windowService.activateApp(bundleID: bundleID)
        }
    }

    // MARK: - Private

    private func loadInstalledApps() {
        let catalog = InstalledAppCatalog()
        let apps = catalog.fetchInstalledApps()
        self.installedApps = apps.map { app in
            InstalledAppItem(
                bundleID: app.bundleID,
                name: app.displayName,
                icon: NSWorkspace.shared.icon(forFile: app.bundlePath),
                path: app.bundlePath
            )
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
