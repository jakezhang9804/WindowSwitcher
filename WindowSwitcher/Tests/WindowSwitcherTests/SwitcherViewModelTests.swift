import AppKit
import AppSwitcherKit
import Foundation
import Testing
@testable import WindowSwitcher

@Suite("Switcher view model search and ordering", .serialized)
@MainActor
struct SwitcherViewModelTests {
    @Test("Persistent application MRU outranks WindowServer order")
    func persistentMRUOrdering() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let service = FakeWindowService(windows: [
            Self.makeWindow(id: 1, appName: "Slack", bundleID: "com.test.slack", title: "General"),
            Self.makeWindow(id: 2, appName: "Chrome", bundleID: "com.test.chrome", title: "Docs")
        ])
        context.mruStore.record(bundleID: "com.test.slack")
        context.mruStore.record(bundleID: "com.test.chrome")

        let model = context.makeModel(service: service)
        model.refreshWindows()

        #expect(model.displayItems.map { $0.displayName } == ["Chrome", "Slack"])
    }

    @Test("Running apps are searchable by bundle ID")
    func runningBundleIDSearch() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let service = FakeWindowService(windows: [
            Self.makeWindow(id: 1, appName: "Cursor", bundleID: "com.todesktop.cursor", title: "Project")
        ])
        let model = context.makeModel(service: service)
        model.refreshWindows()
        model.isSearchActive = true
        model.searchText = "todesktop"

        #expect(model.displayItems.map { $0.displayName } == ["Cursor"])
    }

    @Test("App groups are searchable through member app names")
    func groupMemberSearch() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        try context.settingsStore.save(SwitcherSettings(appGroups: [
            AppGroup(name: "Research", bundleIDs: ["com.apple.Safari"])
        ]))
        let model = context.makeModel(
            service: FakeWindowService(windows: []),
            installedApps: [InstalledApp(bundleID: "com.apple.Safari", displayName: "Safari", bundlePath: "/Applications/Safari.app")]
        )
        model.refreshWindows()
        model.isSearchActive = true
        model.searchText = "Safari"

        #expect(model.displayItems.count == 1)
        #expect(model.displayItems.first?.displayName == "Research")
    }

    @Test("Pinyin initials find installed Chinese-named applications")
    func pinyinSearch() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let model = context.makeModel(
            service: FakeWindowService(windows: []),
            installedApps: [InstalledApp(bundleID: "com.tencent.xinWeChat", displayName: "微信", bundlePath: "/Applications/WeChat.app")]
        )
        model.refreshWindows()
        model.isSearchActive = true
        model.searchText = "wx"

        #expect(model.displayItems.first?.displayName == "微信")
    }

    @Test("An empty active search browses installed applications")
    func emptySearchBrowsesApps() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let model = context.makeModel(
            service: FakeWindowService(windows: []),
            installedApps: [InstalledApp(bundleID: "com.apple.Safari", displayName: "Safari", bundlePath: "/Applications/Safari.app")]
        )
        model.refreshWindows()
        #expect(model.displayItems.isEmpty)

        model.isSearchActive = true
        #expect(model.displayItems.map { $0.displayName } == ["Safari"])
    }

    @Test("Installed application launch failures reach the caller")
    func launchFailureIsReported() async throws {
        struct ExpectedFailure: Error {}
        let context = try TestContext()
        defer { context.cleanup() }
        let service = FakeWindowService(windows: [], launchResult: .failure(ExpectedFailure()))
        let model = context.makeModel(
            service: service,
            installedApps: [InstalledApp(bundleID: "com.test.missing", displayName: "Missing", bundlePath: "/Missing.app")]
        )
        model.refreshWindows()
        model.isSearchActive = true
        model.searchText = "Missing"

        let reportedFailure = await withCheckedContinuation { continuation in
            model.activateResolvedSelection { _, result in
                if case .failure = result {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
        #expect(reportedFailure)
    }

    @MainActor
    private struct TestContext {
        let suiteName: String
        let defaults: UserDefaults
        let settingsStore: UserDefaultsSwitcherSettingsStore
        let mruStore: ApplicationMRUStore
        let previousGroupingMode: Any?

        init() throws {
            suiteName = "SwitcherViewModelTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            settingsStore = UserDefaultsSwitcherSettingsStore(defaults: defaults, storageKey: "settings")
            mruStore = ApplicationMRUStore(defaults: defaults, key: "mru")
            previousGroupingMode = UserDefaults.standard.object(forKey: "tabListGroupingMode")
            UserDefaults.standard.set("byApp", forKey: "tabListGroupingMode")
        }

        func makeModel(
            service: FakeWindowService,
            installedApps: [InstalledApp] = []
        ) -> SwitcherViewModel {
            SwitcherViewModel(
                windowService: service,
                settingsStore: settingsStore,
                mruStore: mruStore,
                installedApps: installedApps
            )
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            if let previousGroupingMode {
                UserDefaults.standard.set(previousGroupingMode, forKey: "tabListGroupingMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "tabListGroupingMode")
            }
        }
    }

    private static func makeWindow(
        id: CGWindowID,
        appName: String,
        bundleID: String,
        title: String
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            title: title,
            appName: appName,
            appPID: pid_t(id),
            appBundleID: bundleID,
            appIcon: nil
        )
    }
}

private final class FakeWindowService: WindowServicing {
    let windows: [WindowInfo]
    let launchResult: Result<Void, Error>
    private(set) var activatedWindow: WindowInfo?
    private(set) var activatedApp: InstalledApp?
    private(set) var activatedGroup: AppGroup?

    init(windows: [WindowInfo], launchResult: Result<Void, Error> = .success(())) {
        self.windows = windows
        self.launchResult = launchResult
    }

    func getAllWindows() -> [WindowInfo] { windows }

    func activateWindow(_ window: WindowInfo) {
        activatedWindow = window
    }

    func activateInstalledApp(_ app: InstalledApp, completion: @escaping (Result<Void, Error>) -> Void) {
        activatedApp = app
        completion(launchResult)
    }

    func activateGroup(_ group: AppGroup) {
        activatedGroup = group
    }
}
