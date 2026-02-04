import AppKit
import KeyboardShortcuts

class HotkeyService {
    
    // MARK: - Properties
    
    private var onShowSwitcher: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        setupDefaultShortcuts()
    }
    
    // MARK: - Setup
    
    private func setupDefaultShortcuts() {
        // Default shortcut is Option + Tab, set in KeyboardShortcuts.Name extension
    }
    
    // MARK: - Public Methods
    
    /// Register callback for show switcher hotkey
    func onShowSwitcher(_ handler: @escaping () -> Void) {
        self.onShowSwitcher = handler
        
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            self?.onShowSwitcher?()
        }
    }
    
    /// Reset all shortcuts to defaults
    func resetToDefaults() {
        KeyboardShortcuts.reset(.showSwitcher)
    }
}
