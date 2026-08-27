import Testing
@testable import AppSwitcherKit

@Suite("Search keyboard policy")
struct SearchKeyboardPolicyTests {
    @Test("Enter activates search before editing")
    func enterActivatesSearch() {
        #expect(SearchKeyboardPolicy.action(for: .enter, searchActive: false) == .activateSearch)
    }

    @Test("Enter is passed to TextField and the input method while searching")
    func enterPassesToInputMethod() {
        #expect(SearchKeyboardPolicy.action(for: .enter, searchActive: true) == .passToTextField)
    }

    @Test("Escape leaves search before the visible hierarchy")
    func escapeHierarchy() {
        #expect(SearchKeyboardPolicy.action(for: .escape, searchActive: true) == .deactivateSearch)
        #expect(SearchKeyboardPolicy.action(for: .escape, searchActive: false) == .deferToHierarchy)
    }
}
