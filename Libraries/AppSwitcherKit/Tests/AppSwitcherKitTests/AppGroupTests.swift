import XCTest
@testable import AppSwitcherKit

final class AppGroupTests: XCTestCase {

    // MARK: - Sanitization rules

    func testSanitizedDropsEmptyGroupsAndTrimsName() {
        let groups = [
            AppGroup(name: "  工作  ", bundleIDs: ["com.test.a", "", "com.test.a", "com.test.b"], screenIndex: 1),
            AppGroup(name: "   ", bundleIDs: ["com.test.c"]),
            AppGroup(name: "空组", bundleIDs: []),
            AppGroup(name: "负屏幕", bundleIDs: ["com.test.d"], screenIndex: -3)
        ]

        let sanitized = AppGroupRules.sanitized(groups)

        XCTAssertEqual(sanitized.count, 2)
        XCTAssertEqual(sanitized[0].name, "工作")
        XCTAssertEqual(sanitized[0].bundleIDs, ["com.test.a", "com.test.b"])
        XCTAssertEqual(sanitized[0].screenIndex, 1)
        XCTAssertEqual(sanitized[1].name, "负屏幕")
        XCTAssertEqual(sanitized[1].screenIndex, 0)
    }

    // MARK: - Persistence

    func testStoreRoundTripWithGroups() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let group = AppGroup(name: "开发", bundleIDs: ["com.test.a", "com.test.b"], screenIndex: 1)
        let input = SwitcherSettings(appGroups: [group])

        try store.save(input)
        let output = store.load()

        XCTAssertEqual(output.appGroups, [group])

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStoreRoundTripPreservesFrames() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let group = AppGroup(
            name: "布局",
            bundleIDs: ["com.test.a", "com.test.b"],
            screenIndex: 0,
            frames: ["com.test.a": AppGroupWindowFrame(x: -1440, y: -259, width: 1440, height: 1518)]
        )
        try store.save(SwitcherSettings(appGroups: [group]))
        let output = store.load()

        XCTAssertEqual(output.appGroups.first?.frames["com.test.a"],
                       AppGroupWindowFrame(x: -1440, y: -259, width: 1440, height: 1518))
        XCTAssertTrue(output.appGroups.first?.hasCapturedLayout ?? false)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSanitizedDropsFramesForNonMembers() {
        let group = AppGroup(
            name: "g",
            bundleIDs: ["com.test.a"],
            frames: [
                "com.test.a": AppGroupWindowFrame(x: 0, y: 0, width: 100, height: 100),
                "com.test.removed": AppGroupWindowFrame(x: 1, y: 1, width: 2, height: 2)
            ]
        )
        let sanitized = AppGroupRules.sanitized([group])
        XCTAssertEqual(Set(sanitized[0].frames.keys), ["com.test.a"])
    }

    func testGroupWithoutFramesKeyDecodes() throws {
        // A group encoded before `frames` existed
        let json = """
        {"id":"\(UUID().uuidString)","name":"g","bundleIDs":["com.test.a"],"screenIndex":1}
        """
        let group = try JSONDecoder().decode(AppGroup.self, from: Data(json.utf8))
        XCTAssertEqual(group.frames, [:])
        XCTAssertFalse(group.hasCapturedLayout)
    }

    func testLegacySettingsWithoutGroupsKeyStillDecode() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Settings JSON written by a version that predates appGroups
        let legacyJSON = """
        {"allowedBundleIDs":["com.test.a"],"appBindings":[{"bundleID":"com.test.a","triggerKey":"A"}]}
        """
        defaults.set(Data(legacyJSON.utf8), forKey: UserDefaultsSwitcherSettingsStore.defaultStorageKey)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let output = store.load()

        XCTAssertEqual(output.allowedBundleIDs, ["com.test.a"])
        XCTAssertEqual(output.appBindings.count, 1)
        XCTAssertEqual(output.appGroups, [])

        defaults.removePersistentDomain(forName: suiteName)
    }
}
