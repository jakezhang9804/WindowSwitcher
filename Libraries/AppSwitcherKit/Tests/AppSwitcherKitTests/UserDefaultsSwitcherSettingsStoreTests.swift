import Foundation
import Testing
@testable import AppSwitcherKit

@Suite("UserDefaults settings store")
struct UserDefaultsSwitcherSettingsStoreTests {
    @Test("Settings save and load round-trip")
    func saveAndLoadRoundTrip() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let input = SwitcherSettings(
            appGroups: [AppGroup(name: "Work", bundleIDs: ["com.test.a", "com.test.b"], screenIndex: 0)]
        )

        try store.save(input)
        let output = store.load()

        #expect(output.appGroups.map(\.name) == ["Work"])
        #expect(output.appGroups.first?.bundleIDs == ["com.test.a", "com.test.b"])
    }

    @Test("Legacy pinned-app fields survive load and later saves")
    func legacyFieldsArePreserved() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = """
        {"allowedBundleIDs":["com.test.a"],"appBindings":[{"bundleID":"com.test.a","triggerKey":"A"}],"appGroups":[]}
        """
        defaults.set(Data(legacy.utf8), forKey: UserDefaultsSwitcherSettingsStore.defaultStorageKey)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        var output = store.load()

        #expect(output.appGroups.isEmpty)
        #expect(output.allowedBundleIDs == ["com.test.a"])
        #expect(output.appBindings == [AppBinding(bundleID: "com.test.a", triggerKey: "A")])

        output.appGroups = [AppGroup(name: "New", bundleIDs: ["com.test.new"])]
        try store.save(output)
        let roundTripped = store.load()

        #expect(roundTripped.allowedBundleIDs == ["com.test.a"])
        #expect(roundTripped.appBindings == [AppBinding(bundleID: "com.test.a", triggerKey: "A")])
        #expect(roundTripped.appGroups.map(\.name) == ["New"])
    }

    @Test("Corrupt data falls back to empty settings")
    func corruptDataFallsBackToDefaults() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not-json".utf8), forKey: UserDefaultsSwitcherSettingsStore.defaultStorageKey)

        let output = UserDefaultsSwitcherSettingsStore(defaults: defaults).load()

        #expect(output == SwitcherSettings())
    }

    @Test("Corrupt current data restores the last known good save")
    func corruptDataRestoresBackup() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let expected = SwitcherSettings(
            allowedBundleIDs: ["com.test.legacy"],
            appGroups: [AppGroup(name: "Recovered", bundleIDs: ["com.test.app"])]
        )
        try store.save(expected)
        defaults.set(Data("truncated".utf8), forKey: UserDefaultsSwitcherSettingsStore.defaultStorageKey)

        let recovered = store.load()

        #expect(recovered == expected)
    }
}
