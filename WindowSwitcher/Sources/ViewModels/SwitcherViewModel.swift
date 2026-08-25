import SwiftUI
import AppSwitcherKit

/// Represents a top-level switcher item — a single window, an app (aggregating
/// its visible windows), or an app group (screen recording).
enum SwitcherItem: Identifiable, Equatable, Hashable {
    case window(WindowInfo)
    case appWindows(bundleID: String, name: String, icon: NSImage?, windows: [WindowInfo])
    case application(InstalledApp, icon: NSImage?)
    case group(AppGroup, icons: [NSImage])

    var id: String {
        switch self {
        case .window(let w): return "window-\(w.id)"
        case .appWindows(let bid, _, _, _): return "appwin-\(bid)"
        case .application(let app, _): return "application-\(app.bundleID)"
        case .group(let g, _): return "group-\(g.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .window(let w): return w.appName
        case .appWindows(_, let name, _, _): return name
        case .application(let app, _): return app.displayName
        case .group(let g, _): return g.name
        }
    }

    var subtitle: String? {
        switch self {
        case .window(let w): return w.title.isEmpty ? nil : w.title
        case .appWindows(_, _, _, let windows):
            return windows.count > 1 ? L10n.windowCountText(windows.count) : windows.first?.title
        case .application:
            return L10n.launchApplication
        case .group(let g, _): return L10n.groupMembers(g.bundleIDs.count)
        }
    }

    var icon: NSImage? {
        switch self {
        case .window(let w): return w.appIcon
        case .appWindows(_, _, let icon, _): return icon
        case .application(_, let icon): return icon
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

    /// The windows this item can drill into. An item with ≥2 windows opens a
    /// secondary detail panel (TabTab's per-app grouping behavior).
    var windows: [WindowInfo] {
        switch self {
        case .window(let w): return [w]
        case .appWindows(_, _, _, let windows): return windows
        case .application, .group: return []
        }
    }

    var representedBundleIDs: Set<String> {
        switch self {
        case .window(let window):
            return Set([window.appBundleID].compactMap { $0?.lowercased() })
        case .appWindows(let bundleID, _, _, _):
            return [bundleID.lowercased()]
        case .application(let app, _):
            return [app.bundleID.lowercased()]
        case .group(let group, _):
            return Set(group.bundleIDs.map { $0.lowercased() })
        }
    }

    static func == (lhs: SwitcherItem, rhs: SwitcherItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            resetSecondary()
            selectedIndex = 0
        }
    }
    @Published var isSearchActive: Bool = false

    /// Top-level selection. Changing it collapses any open secondary panel.
    @Published var selectedIndex: Int = 0 {
        didSet { if oldValue != selectedIndex { resetSecondary() } }
    }

    /// True while the secondary (per-app window) panel is drilled into.
    @Published var secondaryActive: Bool = false
    /// Selection within the secondary window list.
    @Published var secondaryIndex: Int = 0

    @Published private(set) var windows: [WindowInfo] = []

    /// App groups from settings
    private var appGroups: [AppGroup] = []

    /// "byApp" (one row per app, drill into windows) or "flat" (one row per window)
    private var groupingMode: String {
        UserDefaults.standard.string(forKey: "tabListGroupingMode") ?? "byApp"
    }

    /// Bundle IDs (lowercased) that belong to some group — those apps are
    /// represented by the group only, never as a standalone window/app entry
    private var groupedBundleIDs: Set<String> {
        Set(appGroups.flatMap { $0.bundleIDs }.map { $0.lowercased() })
    }

    private func isGrouped(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return groupedBundleIDs.contains(bundleID.lowercased())
    }

    /// Top-level display items: visible windows (flat) or per-app rows (byApp),
    /// then app groups. A non-empty search also includes matching installed apps
    /// that are not already represented by an open window.
    var displayItems: [SwitcherItem] {
        let baseWindows = windows.filter { !isGrouped($0.appBundleID) }

        var items: [SwitcherItem]
        if groupingMode == "byApp" {
            items = aggregateByApp(baseWindows)
        } else {
            items = baseWindows.map { .window($0) }
        }

        items += appGroups.map { group in
            .group(group, icons: group.bundleIDs.compactMap { Self.icon(forBundleID: $0) })
        }

        // Place each group where its frontmost member appears in the WindowServer
        // order instead of appending every group at the end of the MRU ring.
        let rankByWindowID = Dictionary(
            uniqueKeysWithValues: windows.enumerated().map { ($0.element.id, $0.offset) }
        )
        items = items.enumerated().sorted { lhs, rhs in
            let leftRank = rank(of: lhs.element, rankByWindowID: rankByWindowID)
            let rightRank = rank(of: rhs.element, rankByWindowID: rankByWindowID)
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)

        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        let words = query.split(separator: " ").map(String.init)
        let matchingOpenItems = items.filter { item in
            let haystack = matchText(for: item)
            return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
        }

        let representedBundleIDs = Set(baseWindows.compactMap { $0.appBundleID?.lowercased() })
        let matchingApplications = installedApps.lazy
            .filter { !representedBundleIDs.contains($0.bundleID.lowercased()) }
            .filter { !self.isGrouped($0.bundleID) }
            .filter { app in
                let haystack = [app.displayName.lowercased(), app.bundleID.lowercased()]
                return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
            }
            .prefix(20)
            .map { app in
                SwitcherItem.application(app, icon: NSWorkspace.shared.icon(forFile: app.bundlePath))
            }

        return matchingOpenItems + matchingApplications
    }

    /// Collapse windows into one row per app, preserving front-to-back order
    private func aggregateByApp(_ wins: [WindowInfo]) -> [SwitcherItem] {
        var order: [String] = []
        var byKey: [String: [WindowInfo]] = [:]
        for w in wins {
            let key = w.appBundleID ?? "pid-\(w.appPID)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(w)
        }
        return order.map { key in
            let ws = byKey[key] ?? []
            let first = ws.first
            return .appWindows(
                bundleID: key,
                name: first?.appName ?? key,
                icon: first?.appIcon,
                windows: ws
            )
        }
    }

    private func matchText(for item: SwitcherItem) -> [String] {
        switch item {
        case .window(let w):
            return [w.appName.lowercased(), w.title.lowercased()]
        case .appWindows(_, let name, _, let ws):
            return [name.lowercased()] + ws.map { $0.title.lowercased() }
        case .application(let app, _):
            return [app.displayName.lowercased(), app.bundleID.lowercased()]
        case .group(let g, _):
            return [g.name.lowercased()]
        }
    }

    private func rank(of item: SwitcherItem, rankByWindowID: [CGWindowID: Int]) -> Int {
        switch item {
        case .window(let window):
            return rankByWindowID[window.id] ?? .max
        case .appWindows(_, _, _, let windows):
            return windows.compactMap { rankByWindowID[$0.id] }.min() ?? .max
        case .application:
            return .max
        case .group(let group, _):
            let members = Set(group.bundleIDs.map { $0.lowercased() })
            return windows.enumerated().first { _, window in
                guard let bundleID = window.appBundleID?.lowercased() else { return false }
                return members.contains(bundleID)
            }?.offset ?? .max
        }
    }

    var totalCount: Int { displayItems.count }

    var selectedItem: SwitcherItem? {
        let items = displayItems
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    /// Windows of the selected item, only when it's drillable (≥2 windows).
    var expandedWindows: [WindowInfo] {
        let w = selectedItem?.windows ?? []
        return w.count >= 2 ? w : []
    }

    /// The list actually on screen: the app's windows when drilled in, else the
    /// top-level items. Used by number-key jump and the count-driven resize.
    var displayedItems: [SwitcherItem] {
        secondaryActive ? expandedWindows.map { .window($0) } : displayItems
    }

    /// Icon lookup for group members (cached — NSWorkspace lookups add up when
    /// rebuilding the list on every panel open)
    private static let groupIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    private static func icon(forBundleID bundleID: String) -> NSImage? {
        let key = bundleID.lowercased() as NSString
        if let cached = groupIconCache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        groupIconCache.setObject(icon, forKey: key)
        return icon
    }

    private let windowService: WindowService
    private let settingsStore: UserDefaultsSwitcherSettingsStore
    @Published private var installedApps: [InstalledApp] = []
    private static var installedAppCache: [InstalledApp]?
    private static var installedAppLoadTask: Task<[InstalledApp], Never>?

    init(windowService: WindowService, settingsStore: UserDefaultsSwitcherSettingsStore = UserDefaultsSwitcherSettingsStore()) {
        self.windowService = windowService
        self.settingsStore = settingsStore
        preloadInstalledApps()
    }

    private func preloadInstalledApps() {
        if let cached = Self.installedAppCache {
            installedApps = cached
            return
        }

        let task: Task<[InstalledApp], Never>
        if let existing = Self.installedAppLoadTask {
            task = existing
        } else {
            task = Task.detached(priority: .utility) {
                InstalledAppCatalog().fetchInstalledApps()
            }
            Self.installedAppLoadTask = task
        }

        Task { [weak self] in
            let apps = await task.value
            Self.installedAppCache = apps
            Self.installedAppLoadTask = nil
            self?.installedApps = apps
        }
    }

    func refreshWindows() {
        let settings = settingsStore.load()
        self.appGroups = settings.appGroups
        windows = windowService.getAllWindows()
        searchText = ""
        isSearchActive = false
        resetSecondary()
        let items = displayItems
        guard !items.isEmpty else {
            selectedIndex = 0
            return
        }

        // Select the item after the foreground app in the MRU ring. A group can
        // represent that app, so match through all bundle IDs represented by it.
        if let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased(),
           let currentIndex = items.firstIndex(where: { $0.representedBundleIDs.contains(frontBundleID) }),
           items.count > 1 {
            selectedIndex = (currentIndex + 1) % items.count
        } else {
            selectedIndex = 0
        }
    }

    // MARK: - Navigation

    /// Top-level next (Tab / Cmd+Tab cycle). Always operates on the app list.
    func selectNext() {
        resetSecondary()
        let count = displayItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    func selectPrevious() {
        resetSecondary()
        let count = displayItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    /// Down arrow: move within the secondary list if open, else next top-level.
    func moveDown() {
        if secondaryActive {
            let count = expandedWindows.count
            if secondaryIndex < count - 1 { secondaryIndex += 1 }
        } else {
            selectNext()
        }
    }

    /// Up arrow only moves within the current level. Left Arrow / Escape own the
    /// hierarchy transition so navigation never backs out by surprise.
    func moveUp() {
        if secondaryActive {
            if secondaryIndex > 0 { secondaryIndex -= 1 }
        } else {
            selectPrevious()
        }
    }

    /// Right arrow: drill into the selected app's windows (if ≥2).
    func enterSecondary() {
        guard expandedWindows.count >= 2 else { return }
        secondaryActive = true
        secondaryIndex = 0
    }

    /// Left arrow / Escape: back out of the secondary panel.
    func exitSecondary() {
        secondaryActive = false
        secondaryIndex = 0
    }

    private func resetSecondary() {
        if secondaryActive { secondaryActive = false }
        secondaryIndex = 0
    }

    /// Set the selection in whichever list is currently displayed (used by the
    /// number-key jump).
    func selectDisplayed(_ index: Int) {
        if secondaryActive { secondaryIndex = index } else { selectedIndex = index }
    }

    // MARK: - Activation

    /// Activate the current selection, resolving the secondary panel: a drilled-in
    /// window wins, otherwise the app's frontmost window / the group.
    func activateResolvedSelection() {
        guard let item = selectedItem else { return }
        if secondaryActive, expandedWindows.indices.contains(secondaryIndex) {
            windowService.activateWindow(expandedWindows[secondaryIndex])
            return
        }
        activate(item)
    }

    /// Activate a specific item (top-level tap or default action)
    func activate(_ item: SwitcherItem) {
        switch item {
        case .window(let window):
            windowService.activateWindow(window)
        case .appWindows(_, _, _, let windows):
            if let first = windows.first { windowService.activateWindow(first) }
        case .application(let app, _):
            windowService.activateInstalledApp(app)
        case .group(let group, _):
            windowService.activateGroup(group)
        }
    }

}
