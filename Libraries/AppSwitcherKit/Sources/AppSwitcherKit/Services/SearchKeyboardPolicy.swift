public enum SearchKeyboardKey: Sendable {
    case enter
    case escape
}

public enum SearchKeyboardAction: Equatable, Sendable {
    /// Enter should be consumed and used to focus the search field.
    case activateSearch
    /// Let SwiftUI TextField and the current input method commit marked text.
    case passToTextField
    /// Escape should be consumed, clear the query, and leave search mode.
    case deactivateSearch
    /// Search is inactive; the visible hierarchy owns Escape.
    case deferToHierarchy
}

public enum SearchKeyboardPolicy {
    public static func action(for key: SearchKeyboardKey, searchActive: Bool) -> SearchKeyboardAction {
        switch (key, searchActive) {
        case (.enter, false): return .activateSearch
        case (.enter, true): return .passToTextField
        case (.escape, true): return .deactivateSearch
        case (.escape, false): return .deferToHierarchy
        }
    }
}
