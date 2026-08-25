import AppKit

/// Hotkey service that implements proper Option+Tab window switching behavior:
///
/// **Normal mode (panel shown, search bar inactive by default):**
/// - Option+Tab keyDown → show switcher panel (first press)
/// - Option+Tab again → cycle next (each discrete press)
/// - Long-press Option+Tab → cycle using the system key-repeat events
/// - Option+Tab keyUp → stop auto-repeat Timer
/// - Option+Shift+Tab → cycle previous
/// - Number keys 1-9 → jump to Nth item and confirm (when search inactive)
/// - Option released → confirm selection and dismiss
/// - Enter → activate search; the focused field submits after IME composition is committed
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

    /// Arrow-key navigation (drives per-app drill-down in by-app grouping).
    /// Handled here because the tap swallows arrows while the trigger is held.
    private var upArrowHandler: (() -> Void)?
    private var downArrowHandler: (() -> Void)?
    private var leftArrowHandler: (() -> Void)?
    private var rightArrowHandler: (() -> Void)?

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

    /// Fallback poll timer that watches the hardware modifier state while the
    /// switcher is shown. flagsChanged delivery via NSEvent monitors is not
    /// reliable: global monitors go silent under secure event input, and a
    /// non-activating key panel is not guaranteed to receive modifier events
    /// locally. Release-to-confirm must not depend on event delivery alone.
    private var modifierPollTimer: Timer?
    private let modifierPollInterval: TimeInterval = 0.03

    /// CGEventTap — the primary input path. Sees and can consume every key
    /// event before the system acts on it, which is what makes Command+Tab
    /// takeover possible and modifier-release detection reliable (NSEvent
    /// monitor delivery has proven flaky on some systems).
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?

    var isEventTapActive: Bool {
        guard let eventTap else { return false }
        return CFMachPortIsValid(eventTap) && CGEvent.tapIsEnabled(tap: eventTap)
    }

    /// Track whether the switcher is currently shown
    private(set) var isSwitcherActive = false

    /// Whether the hotkey's modifiers have been observed held while the switcher
    /// is active. Releasing them only confirms the selection when armed — this
    /// prevents a stray modifier press from confirming when the panel was opened
    /// without the hotkey (e.g. from the menu bar).
    private var isConfirmArmed = false

    /// Latched once a release-confirm fires for the current panel session.
    /// Multiple detection paths (tap, monitor, poll) observe the same release
    /// at slightly different times — without the latch, a stale poll reading
    /// can re-arm between them and double-fire the confirmation.
    private var hasConfirmedThisSession = false

    /// Whether the trigger is Command+Tab (taking over the system app
    /// switcher) instead of the default Option+Tab
    private var useCommandTab: Bool {
        UserDefaults.standard.bool(forKey: "useCommandTab")
    }

    /// The modifier that must be held to drive the switcher and whose release
    /// confirms the selection. Window switching already requires Accessibility,
    /// so CGEventTap is the single hotkey source instead of a duplicate fallback.
    private var hotkeyModifiers: NSEvent.ModifierFlags {
        useCommandTab ? .command : .option
    }

    /// The modifiers currently held according to the event system's session
    /// state. Unlike NSEvent.modifierFlags (stale for background apps) and
    /// NSEvent monitors (delivery can silently stop), this queries the actual
    /// key state and always works.
    private static func currentHeldModifiers() -> NSEvent.ModifierFlags {
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { flags.insert(.function) }
        return flags
    }

    func onShowSwitcher(_ handler: @escaping () -> Void) {
        self.showHandler = handler
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

    func onUpArrow(_ handler: @escaping () -> Void) { self.upArrowHandler = handler }
    func onDownArrow(_ handler: @escaping () -> Void) { self.downArrowHandler = handler }
    func onLeftArrow(_ handler: @escaping () -> Void) { self.leftArrowHandler = handler }
    func onRightArrow(_ handler: @escaping () -> Void) { self.rightArrowHandler = handler }

    func onActivateSearch(_ handler: @escaping () -> Void) {
        self.activateSearchHandler = handler
    }

    func onDeactivateSearch(_ handler: @escaping () -> Void) {
        self.deactivateSearchHandler = handler
    }

    /// Called when the switcher panel is shown — start monitoring
    func switcherDidShow() {
        isSwitcherActive = true
        hasConfirmedThisSession = false
        let modifiers = hotkeyModifiers
        // OR, not overwrite: the event tap arms before requesting the show,
        // and that signal is more reliable than the session flags state
        isConfirmArmed = isConfirmArmed
            || (!modifiers.isEmpty && Self.currentHeldModifiers().contains(modifiers))
        if isEventTapActive {
            stopMonitors()
            stopModifierPollTimer()
        } else {
            startMonitors()
            startModifierPollTimer()
        }
        NSLog("[WS][Hotkey] switcherDidShow — fallback=\(!isEventTapActive) (confirmArmed=\(isConfirmArmed), tap=\(isEventTapActive))")
    }

    /// Called when the switcher panel is hidden
    func switcherDidHide() {
        isSwitcherActive = false
        isConfirmArmed = false
        stopModifierPollTimer()
        stopMonitors()
        NSLog("[WS][Hotkey] switcherDidHide — monitors stopped")
    }

    // MARK: - Event Tap (primary input path)

    /// Install the event tap. Accessibility trust is required both for the tap
    /// and for WindowSwitcher to enumerate and activate windows.
    func startEventTap() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleTapEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[WS][Hotkey] Event tap creation FAILED — Accessibility permission is required")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[WS][Hotkey] Event tap started (trigger=\(useCommandTab ? "Command" : "Option")+Tab)")
    }

    func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = tapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        tapRunLoopSource = nil
    }

    /// Runs on the main thread (the tap's run loop source is on the main loop).
    /// Returning nil consumes the event — that is what suppresses the system
    /// app switcher when the trigger is Command+Tab.
    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap whose callback stalls — re-enable and pass
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            if !isEventTapActive {
                DispatchQueue.main.async { [weak self] in
                    self?.stopEventTap()
                    self?.startEventTap()
                }
                NSLog("[WS][Hotkey] Event tap invalid after disable — rebuilding")
            } else {
                NSLog("[WS][Hotkey] Event tap re-enabled after system disable")
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            // The tap sees every modifier transition — the reliable
            // release-to-confirm source. Never consume these.
            let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                .intersection(.deviceIndependentFlagsMask)
            updateConfirmState(heldFlags: nsFlags, source: "tap")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let triggerFlag: CGEventFlags = useCommandTab ? .maskCommand : .maskAlternate
        let triggerHeld = event.flags.contains(triggerFlag)

        // Trigger+Tab → show or cycle (Shift reverses). Consuming the event
        // is what blocks the system Cmd+Tab switcher in Command mode. Key
        // repeat arrives as extra keyDowns, so holding Tab cycles naturally.
        if keyCode == 48 && triggerHeld {
            if isSwitcherActive {
                if event.flags.contains(.maskShift) {
                    shiftTabHandler?()
                } else {
                    tabHandler?()
                }
            } else {
                NSLog("[WS][Hotkey] Tap: \(useCommandTab ? "Cmd" : "Option")+Tab — showing switcher")
                isConfirmArmed = true
                showHandler?()
            }
            return nil
        }

        if isSwitcherActive {
            // Shared key handling (numbers, Enter, Escape, Tab) straight from
            // the CGEvent fields — NSEvent(cgEvent:) bridging is unreliable
            // for tap events and silently dropped keys.
            let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                .intersection(.deviceIndependentFlagsMask)
            if handleKey(keyCode: UInt16(keyCode), flags: nsFlags, characters: nil) {
                return nil
            }
            // Swallow any other combo while the trigger modifier is held so
            // shortcuts like Cmd+Q can't hit the frontmost app mid-switch
            if triggerHeld {
                NSLog("[WS][Hotkey] Tap: swallowing keyCode=\(keyCode) (trigger modifier held)")
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Modifier Poll Timer (release-to-confirm fallback)

    private func startModifierPollTimer() {
        stopModifierPollTimer()

        let timer = Timer(timeInterval: modifierPollInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isSwitcherActive else { return }
            self.updateConfirmState(heldFlags: Self.currentHeldModifiers(), source: "poll")
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        modifierPollTimer = timer
    }

    private func stopModifierPollTimer() {
        modifierPollTimer?.invalidate()
        modifierPollTimer = nil
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
        updateConfirmState(
            heldFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            source: "monitor"
        )
    }

    /// Shared release-to-confirm logic, driven by the event tap (primary),
    /// the flagsChanged monitors, and the poll timer (fallbacks). Runs on the
    /// main thread in all cases, so arming state needs no synchronization.
    private func updateConfirmState(heldFlags: NSEvent.ModifierFlags, source: String) {
        guard isSwitcherActive, !hasConfirmedThisSession else { return }

        let modifiers = hotkeyModifiers
        guard !modifiers.isEmpty else { return }

        // Hotkey modifiers are (still) held — arm the release-to-confirm behavior
        if heldFlags.contains(modifiers) {
            isConfirmArmed = true
            return
        }

        // Modifiers released — only confirm if they were held while the switcher was active
        guard isConfirmArmed else { return }
        isConfirmArmed = false
        hasConfirmedThisSession = true

        let searchActive = isSearchActiveProvider?() ?? false

        // Only auto-confirm if search is NOT active
        if !searchActive {
            NSLog("[WS][Hotkey] Hotkey modifiers released (\(source)) — confirming selection")
            DispatchQueue.main.async { [weak self] in
                self?.confirmHandler?()
            }
        } else {
            NSLog("[WS][Hotkey] Hotkey modifiers released (\(source)) — search active, not confirming")
        }
    }

    /// Handle keyDown events while switcher is active (NSEvent monitor path).
    /// Returns true if the event was consumed.
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        handleKey(
            keyCode: event.keyCode,
            flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            characters: event.charactersIgnoringModifiers
        )
    }

    /// Shared key handling for the tap and monitor paths. The tap passes raw
    /// CGEvent fields — bridging tap events through NSEvent(cgEvent:) proved
    /// unreliable and silently dropped keys.
    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard isSwitcherActive else { return false }

        let searchActive = isSearchActiveProvider?() ?? false

        // Enter (keyCode 36)
        if keyCode == 36 {
            if searchActive {
                // Let the focused TextField and input method handle Return. Its
                // onSubmit callback confirms only after marked text is committed.
                return false
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

        // Arrow keys: navigate the list and drill into per-app windows.
        // Only when search is inactive (otherwise arrows move the text cursor).
        // Handled here — not via SwiftUI — because the tap swallows keys while
        // the trigger modifier is held (the TabTab hold-and-navigate model).
        if !searchActive {
            switch keyCode {
            case 126: // up
                DispatchQueue.main.async { [weak self] in self?.upArrowHandler?() }
                return true
            case 125: // down
                DispatchQueue.main.async { [weak self] in self?.downArrowHandler?() }
                return true
            case 124: // right
                DispatchQueue.main.async { [weak self] in self?.rightArrowHandler?() }
                return true
            case 123: // left
                DispatchQueue.main.async { [weak self] in self?.leftArrowHandler?() }
                return true
            default: break
            }
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

        // Tab (keyCode 48) — cycle through results in both modes.
        if keyCode == 48 {
            if flags.contains(.shift) {
                NSLog("[WS][Hotkey] Shift+Tab — previous")
                DispatchQueue.main.async { [weak self] in
                    self?.shiftTabHandler?()
                }
            } else {
                NSLog("[WS][Hotkey] Tab — next")
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
            if flags.isEmpty || flags == .shift {
                // Plain key or Shift+key with no other modifiers
                if let chars = characters, !chars.isEmpty {
                    // Consume printable characters so they don't go to TextField
                    NSLog("[WS][Hotkey] Consuming key '\(chars)' (search inactive)")
                    return true
                }

                // CGEvent tap callbacks do not always bridge characters. The
                // ANSI printable key range still must not leak into whatever
                // app is behind a switcher opened from the menu bar.
                if keyCode <= 50 {
                    NSLog("[WS][Hotkey] Consuming printable keyCode=\(keyCode) (search inactive)")
                    return true
                }
            }
        }

        // Let all other keys pass through (for search field text input)
        return false
    }
}
