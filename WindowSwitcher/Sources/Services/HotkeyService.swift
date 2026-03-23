import AppKit
import KeyboardShortcuts

/// Hotkey service that implements proper Option+Tab window switching behavior:
///
/// **Normal mode (panel shown, search bar inactive by default):**
/// - Option+Tab keyDown → show switcher panel (first press)
/// - Option+Tab again → cycle next (each discrete press)
/// - Long-press Option+Tab → auto-repeat cycling via Timer
/// - Option+Tab keyUp → stop auto-repeat Timer
/// - Option+Shift+Tab → cycle previous
/// - Number keys 1-9 → jump to Nth item and confirm (when search inactive)
/// - Option released → confirm selection and dismiss
/// - Enter → activate search bar (when search inactive) or confirm selection (when search active)
/// - Escape → deactivate search (if active) or dismiss panel
///
/// Search bar is visible but **inactive** by default. User presses Enter to
/// activate it, then can type to filter windows/apps.
final class HotkeyService {

    private var showHandler: (() -> Void)?
    private var confirmHandler: (() -> Void)?
    private var tabHandler: (() -> Void)?
    private var shiftTabHandler: (() -> Void)?
    private var numberHandler: ((Int) -> Void)?
    private var escapeHandler: (() -> Void)?

    /// Called when Enter is pressed and search is not active — should activate search
    private var activateSearchHandler: (() -> Void)?

    /// Called when Escape is pressed and search is active — should deactivate search
    private var deactivateSearchHandler: (() -> Void)?

    /// Provider that returns whether search is currently active
    var isSearchActiveProvider: (() -> Bool)?

    /// Global event monitor for flagsChanged (detect Option release)
    private var globalFlagsMonitor: Any?
    /// Local event monitor for flagsChanged
    private var localFlagsMonitor: Any?
    /// Global event monitor for keyDown (Enter, Escape, numbers)
    private var globalKeyMonitor: Any?
    /// Local event monitor for keyDown
    private var localKeyMonitor: Any?

    /// Timer for simulating long-press Tab repeat
    private var tabRepeatTimer: Timer?
    /// Initial delay before repeat starts (matches macOS key repeat delay)
    private let repeatInitialDelay: TimeInterval = 0.35
    /// Interval between repeats (matches macOS key repeat rate)
    private let repeatInterval: TimeInterval = 0.07

    /// Track whether the switcher is currently shown
    private(set) var isSwitcherActive = false

    /// Track whether the search field has focus (user is typing)
    var isSearchFieldFocused = false

    func onShowSwitcher(_ handler: @escaping () -> Void) {
        self.showHandler = handler

        // KeyboardShortcuts uses Carbon EventHotKey for Option+Tab detection.
        // Carbon hotkeys fire once on keyDown and don't repeat on long-press.
        // We use a Timer to simulate long-press repeat behavior.
        KeyboardShortcuts.onKeyDown(for: .showSwitcher) { [weak self] in
            guard let self = self else { return }
            NSLog("[WS][Hotkey] Option+Tab keyDown (active=\(self.isSwitcherActive))")
            if self.isSwitcherActive {
                // Panel already visible → cycle to next item immediately
                self.tabHandler?()
                // Start repeat timer for long-press
                self.startTabRepeatTimer()
            } else {
                // Panel not visible → show it
                self.showHandler?()
            }
        }

        // When Tab is released → stop the repeat timer
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            guard let self = self else { return }
            NSLog("[WS][Hotkey] Option+Tab keyUp — stopping repeat timer")
            self.stopTabRepeatTimer()
        }

        NSLog("[WS][Hotkey] Registered KeyboardShortcuts for Option+Tab")
    }

    func onConfirmSelection(_ handler: @escaping () -> Void) {
        self.confirmHandler = handler
    }

    func onTabPress(_ handler: @escaping () -> Void) {
        self.tabHandler = handler
    }

    func onShiftTabPress(_ handler: @escaping () -> Void) {
        self.shiftTabHandler = handler
    }

    func onNumberPress(_ handler: @escaping (Int) -> Void) {
        self.numberHandler = handler
    }

    func onEscape(_ handler: @escaping () -> Void) {
        self.escapeHandler = handler
    }

    func onActivateSearch(_ handler: @escaping () -> Void) {
        self.activateSearchHandler = handler
    }

    func onDeactivateSearch(_ handler: @escaping () -> Void) {
        self.deactivateSearchHandler = handler
    }

    /// Called when the switcher panel is shown — start monitoring
    func switcherDidShow() {
        isSwitcherActive = true
        isSearchFieldFocused = false
        startMonitors()
        NSLog("[WS][Hotkey] switcherDidShow — monitors started")
    }

    /// Called when the switcher panel is hidden
    func switcherDidHide() {
        isSwitcherActive = false
        isSearchFieldFocused = false
        stopTabRepeatTimer()
        stopMonitors()
        NSLog("[WS][Hotkey] switcherDidHide — monitors stopped")
    }

    func resetToDefaults() {
        KeyboardShortcuts.reset(.showSwitcher)
    }

    // MARK: - Tab Repeat Timer

    private func startTabRepeatTimer() {
        stopTabRepeatTimer()

        // After initial delay, start repeating
        tabRepeatTimer = Timer.scheduledTimer(withTimeInterval: repeatInitialDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.isSwitcherActive else { return }
            // Switch to fast repeat
            self.tabRepeatTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                guard let self = self, self.isSwitcherActive else {
                    self?.stopTabRepeatTimer()
                    return
                }
                NSLog("[WS][Hotkey] Tab repeat tick")
                self.tabHandler?()
            }
        }
    }

    private func stopTabRepeatTimer() {
        tabRepeatTimer?.invalidate()
        tabRepeatTimer = nil
    }

    // MARK: - NSEvent Monitors (flags, Enter, Escape, numbers)

    private func startMonitors() {
        stopMonitors()

        // Global flags monitor: detect Option release
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local flags monitor: detect Option release when panel has focus
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Global key monitor: handle Enter, Escape, numbers when other apps have focus
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        // Local key monitor: handle keys when panel has focus
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyDown(event) == true {
                return nil // consume the event
            }
            return event
        }

        NSLog("[WS][Hotkey] All monitors started")
    }

    private func stopMonitors() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // If Option is no longer held and the switcher is active
        if !flags.contains(.option) && isSwitcherActive {
            // Stop any repeat timer
            stopTabRepeatTimer()

            let searchActive = isSearchActiveProvider?() ?? false

            // Only auto-confirm if search is NOT active
            if !searchActive {
                NSLog("[WS][Hotkey] Option released — confirming selection")
                DispatchQueue.main.async { [weak self] in
                    self?.confirmHandler?()
                }
            } else {
                NSLog("[WS][Hotkey] Option released — search active, not confirming")
            }
        }
    }

    /// Handle keyDown events while switcher is active.
    /// Returns true if the event was consumed.
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isSwitcherActive else { return false }

        let keyCode = event.keyCode
        let searchActive = isSearchActiveProvider?() ?? false

        // Enter (keyCode 36)
        if keyCode == 36 {
            if searchActive {
                // Search is active → confirm current selection
                NSLog("[WS][Hotkey] Enter pressed — confirming selection (search active)")
                DispatchQueue.main.async { [weak self] in
                    self?.confirmHandler?()
                }
            } else {
                // Search is not active → activate search bar
                NSLog("[WS][Hotkey] Enter pressed — activating search")
                DispatchQueue.main.async { [weak self] in
                    self?.activateSearchHandler?()
                }
            }
            return true
        }

        // Escape (keyCode 53)
        if keyCode == 53 {
            if searchActive {
                // Search is active → deactivate search
                NSLog("[WS][Hotkey] Escape pressed — deactivating search")
                DispatchQueue.main.async { [weak self] in
                    self?.deactivateSearchHandler?()
                }
            } else {
                // Search is not active → dismiss panel
                NSLog("[WS][Hotkey] Escape pressed — dismissing")
                DispatchQueue.main.async { [weak self] in
                    self?.escapeHandler?()
                }
            }
            return true
        }

        // Number keys 1-9: only work as shortcuts when search is NOT active
        if !searchActive {
            let numberKeyCodes: [UInt16: Int] = [
                18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
            ]
            if let number = numberKeyCodes[keyCode] {
                NSLog("[WS][Hotkey] Number \(number) pressed — jumping to item")
                DispatchQueue.main.async { [weak self] in
                    self?.numberHandler?(number)
                }
                return true
            }
        }

        // Tab (keyCode 48) in search mode — cycle through results
        if keyCode == 48 && searchActive {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) {
                NSLog("[WS][Hotkey] Shift+Tab in search — previous")
                DispatchQueue.main.async { [weak self] in
                    self?.shiftTabHandler?()
                }
            } else {
                NSLog("[WS][Hotkey] Tab in search — next")
                DispatchQueue.main.async { [weak self] in
                    self?.tabHandler?()
                }
            }
            return true
        }

        // When search is not active, consume all letter/number keys to prevent them
        // from reaching any hidden text field
        if !searchActive {
            // Let modifier keys pass through
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.isEmpty || flags == .shift {
                // Plain key or Shift+key with no other modifiers
                if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    // Consume printable characters so they don't go to TextField
                    NSLog("[WS][Hotkey] Consuming key '\(chars)' (search inactive)")
                    return true
                }
            }
        }

        // Let all other keys pass through (for search field text input)
        return false
    }
}
