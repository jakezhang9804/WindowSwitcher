import Foundation
import Testing
@testable import AppSwitcherKit

@Suite("App group rules and persistence")
struct AppGroupTests {
    @Test("Sanitization drops invalid groups, trims names, and clamps screen indexes")
    func sanitizedDropsInvalidGroupsAndTrimsName() {
        let groups = [
            AppGroup(name: "  工作  ", bundleIDs: ["com.test.a", "", "com.test.a", "com.test.b"], screenIndex: 1),
            AppGroup(name: "   ", bundleIDs: ["com.test.c"]),
            AppGroup(name: "空组", bundleIDs: []),
            AppGroup(name: "负屏幕", bundleIDs: ["com.test.d"], screenIndex: -3)
        ]

        let sanitized = AppGroupRules.sanitized(groups)

        #expect(sanitized.count == 2)
        #expect(sanitized[0].name == "工作")
        #expect(sanitized[0].bundleIDs == ["com.test.a", "com.test.b"])
        #expect(sanitized[0].screenIndex == 1)
        #expect(sanitized[1].name == "负屏幕")
        #expect(sanitized[1].screenIndex == 0)
    }

    @Test("Bundle IDs deduplicate and preserve frames case-insensitively")
    func sanitizationIsCaseInsensitive() {
        let frame = AppGroupWindowFrame(x: 10, y: 20, width: 800, height: 600)
        let group = AppGroup(
            name: "Work",
            bundleIDs: [" COM.Test.App ", "com.test.app"],
            frames: ["com.test.APP": frame]
        )

        let sanitized = AppGroupRules.sanitized([group])

        #expect(sanitized.count == 1)
        #expect(sanitized[0].bundleIDs == ["COM.Test.App"])
        #expect(sanitized[0].frames["com.test.APP"] == frame)
    }

    @Test("An application belongs to only the first saved group")
    func sanitizationRemovesCrossGroupDuplicates() {
        let groups = [
            AppGroup(name: "Work", bundleIDs: ["com.test.shared", "com.test.work"]),
            AppGroup(name: "Personal", bundleIDs: ["COM.TEST.SHARED", "com.test.personal"]),
            AppGroup(name: "Duplicate only", bundleIDs: ["com.test.shared"])
        ]

        let sanitized = AppGroupRules.sanitized(groups)

        #expect(sanitized.map(\.name) == ["Work", "Personal"])
        #expect(sanitized[0].bundleIDs == ["com.test.shared", "com.test.work"])
        #expect(sanitized[1].bundleIDs == ["com.test.personal"])
    }

    @Test("Duplicate group IDs and blank display IDs are removed")
    func sanitizationRemovesDuplicateGroupIDs() {
        let id = UUID()
        let groups = [
            AppGroup(id: id, name: "First", bundleIDs: ["com.test.first"], displayID: "   "),
            AppGroup(id: id, name: "Duplicate", bundleIDs: ["com.test.second"])
        ]

        let sanitized = AppGroupRules.sanitized(groups)

        #expect(sanitized.map(\.name) == ["First"])
        #expect(sanitized[0].displayID == nil)
    }

    @Test("Store round-trips groups")
    func storeRoundTripWithGroups() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let group = AppGroup(
            name: "开发",
            bundleIDs: ["com.test.a", "com.test.b"],
            screenIndex: 1,
            displayID: "DISPLAY-UUID-1"
        )

        try store.save(SwitcherSettings(appGroups: [group]))

        #expect(store.load().appGroups == [group])
    }

    @Test("Store round-trips recorded frames")
    func storeRoundTripPreservesFrames() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let frame = AppGroupWindowFrame(
            x: -1440,
            y: -259,
            width: 1440,
            height: 1518,
            relativeX: 0.25,
            relativeY: 0.75
        )
        let group = AppGroup(
            name: "布局",
            bundleIDs: ["com.test.a", "com.test.b"],
            screenIndex: 0,
            frames: ["com.test.a": frame]
        )
        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)

        try store.save(SwitcherSettings(appGroups: [group]))
        let output = store.load()

        #expect(output.appGroups.first?.frames["com.test.a"] == frame)
        #expect(output.appGroups.first?.hasCapturedLayout == true)
    }

    @Test("Frames saved before relative coordinates existed still decode")
    func legacyAbsoluteFrameDecodes() throws {
        let json = """
        {"x":10,"y":20,"width":800,"height":600}
        """

        let frame = try JSONDecoder().decode(AppGroupWindowFrame.self, from: Data(json.utf8))

        #expect(frame.relativeX == nil)
        #expect(frame.relativeY == nil)
    }

    @Test("Sanitization drops frames for removed members")
    func sanitizedDropsFramesForNonMembers() {
        let group = AppGroup(
            name: "g",
            bundleIDs: ["com.test.a"],
            frames: [
                "com.test.a": AppGroupWindowFrame(x: 0, y: 0, width: 100, height: 100),
                "com.test.removed": AppGroupWindowFrame(x: 1, y: 1, width: 2, height: 2)
            ]
        )

        let sanitized = AppGroupRules.sanitized([group])

        #expect(Set(sanitized[0].frames.keys) == Set(["com.test.a"]))
    }

    @Test("Groups saved before frames existed still decode")
    func groupWithoutFramesKeyDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"g","bundleIDs":["com.test.a"],"screenIndex":1}
        """

        let group = try JSONDecoder().decode(AppGroup.self, from: Data(json.utf8))

        #expect(group.frames.isEmpty)
        #expect(!group.hasCapturedLayout)
    }

    @Test("Legacy settings without app groups still decode and preserve old fields")
    func legacySettingsWithoutGroupsKeyStillDecode() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyJSON = """
        {"allowedBundleIDs":["com.test.a"],"appBindings":[{"bundleID":"com.test.a","triggerKey":"A"}]}
        """
        defaults.set(Data(legacyJSON.utf8), forKey: UserDefaultsSwitcherSettingsStore.defaultStorageKey)

        let output = UserDefaultsSwitcherSettingsStore(defaults: defaults).load()

        #expect(output.appGroups.isEmpty)
        #expect(output.allowedBundleIDs == ["com.test.a"])
        #expect(output.appBindings == [AppBinding(bundleID: "com.test.a", triggerKey: "A")])
    }
}
