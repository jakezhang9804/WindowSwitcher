import AppKit
import KeyboardShortcuts

/// Hotkey service wrapper
final class HotkeyService {

    private var onShowSwitcher: (() -> Void)?

    func onShowSwitcher(_ handler: @escaping () -> Void) {
        self.onShowSwitcher = handler
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            self?.onShowSwitcher?()
        }
    }

    func resetToDefaults() {
        KeyboardShortcuts.reset(.showSwitcher)
    }
}
