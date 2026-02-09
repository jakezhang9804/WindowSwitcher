import XCTest
@testable import AppSwitcherKit

final class UserDefaultsSwitcherSettingsStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let input = SwitcherSettings(
            allowedBundleIDs: ["com.test.a", "com.test.b"],
            appBindings: [
                AppBinding(bundleID: "com.test.a", triggerKey: "a"),
                AppBinding(bundleID: "com.test.b", triggerKey: "9")
            ]
        )

        try store.save(input)
        let output = store.load()

        XCTAssertEqual(output.allowedBundleIDs, ["com.test.a", "com.test.b"])
        XCTAssertEqual(
            output.appBindings,
            [
                AppBinding(bundleID: "com.test.a", triggerKey: "A"),
                AppBinding(bundleID: "com.test.b", triggerKey: "9")
            ]
        )

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSaveThrowsWhenBindingsConflict() {
        let suiteName = "AppSwitcherKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsSwitcherSettingsStore(defaults: defaults)
        let conflicting = SwitcherSettings(
            allowedBundleIDs: [],
            appBindings: [
                AppBinding(bundleID: "com.test.a", triggerKey: "k"),
                AppBinding(bundleID: "com.test.b", triggerKey: "K")
            ]
        )

        XCTAssertThrowsError(try store.save(conflicting))

        defaults.removePersistentDomain(forName: suiteName)
    }
}
