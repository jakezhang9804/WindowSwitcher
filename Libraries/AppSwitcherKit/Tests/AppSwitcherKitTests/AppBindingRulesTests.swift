import XCTest
@testable import AppSwitcherKit

final class AppBindingRulesTests: XCTestCase {
    func testNormalizeTriggerKeySupportsLettersAndNumbers() {
        XCTAssertEqual(AppBindingRules.normalizeTriggerKey("a"), "A")
        XCTAssertEqual(AppBindingRules.normalizeTriggerKey(" 9 "), "9")
        XCTAssertEqual(AppBindingRules.normalizeTriggerKey("Z"), "Z")
    }

    func testNormalizeTriggerKeyRejectsInvalidCharacters() {
        XCTAssertNil(AppBindingRules.normalizeTriggerKey(""))
        XCTAssertNil(AppBindingRules.normalizeTriggerKey("   "))
        XCTAssertNil(AppBindingRules.normalizeTriggerKey("@@@"))
        XCTAssertNil(AppBindingRules.normalizeTriggerKey("💡"))
    }

    func testConflictingBundleIDsReturnsAllConflictedBundles() {
        let bindings = [
            AppBinding(bundleID: "com.test.a", triggerKey: "A"),
            AppBinding(bundleID: "com.test.b", triggerKey: "a"),
            AppBinding(bundleID: "com.test.c", triggerKey: "9")
        ]

        let conflicts = AppBindingRules.conflictingBundleIDs(for: bindings)

        XCTAssertEqual(conflicts, Set(["com.test.a", "com.test.b"]))
        XCTAssertTrue(AppBindingRules.hasConflicts(bindings))
    }

    func testNormalizedBindingsDropsDuplicatesAndInvalidItems() {
        let bindings = [
            AppBinding(bundleID: "com.test.a", triggerKey: "a"),
            AppBinding(bundleID: "com.test.a", triggerKey: "z"),
            AppBinding(bundleID: "com.test.b", triggerKey: "A"),
            AppBinding(bundleID: "", triggerKey: "1"),
            AppBinding(bundleID: "com.test.c", triggerKey: "$")
        ]

        let normalized = AppBindingRules.normalizedBindings(bindings)

        XCTAssertEqual(
            normalized,
            [
                AppBinding(bundleID: "com.test.a", triggerKey: "A")
            ]
        )
    }
}
