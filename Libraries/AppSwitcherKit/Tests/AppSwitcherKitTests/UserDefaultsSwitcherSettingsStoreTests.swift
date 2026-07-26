import XCTest
@testable import AppSwitcherKit

final class UserDefaultsSwitcherSettingsStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let input = SwitcherSettings(
            appGroups: [
                AppGroup(name: "Work", bundleIDs: ["com.test.a", "com.test.b"], screenIndex: 0)
            ]
        )

        try store.save(input)
        let output = store.load()

        XCTAssertEqual(output.appGroups.map(\.name), ["Work"])
        XCTAssertEqual(output.appGroups.first?.bundleIDs, ["com.test.a", "com.test.b"])

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadIgnoresLegacyKeys() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Settings persisted by an older version carried allowedBundleIDs /
        // appBindings — those keys must decode without error and be dropped.
        let legacy = """
        {"allowedBundleIDs":["com.test.a"],"appBindings":[{"bundleID":"com.test.a","triggerKey":"A"}],"appGroups":[]}
        """
        defaults.set(Data(legacy.utf8), forKey: UserDefaultsSwitcherSettingsStore.defaultStorageKey)

        let output = UserDefaultsSwitcherSettingsStore(defaults: defaults).load()
        XCTAssertTrue(output.appGroups.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
