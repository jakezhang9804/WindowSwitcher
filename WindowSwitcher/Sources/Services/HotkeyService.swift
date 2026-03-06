import AppKit
import KeyboardShortcuts

/// 快捷键服务封装
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
