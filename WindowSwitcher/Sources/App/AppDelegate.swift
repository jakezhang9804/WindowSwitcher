import AppKit
import SwiftUI
import KeyboardShortcuts
import AppSwitcherKit
import PermissionFlowScreenRecordingStatus

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Must keep a strong reference to statusItem, otherwise the menu bar icon will disappear
    private var statusItem: NSStatusItem!
    private var switcherPanel: KeyablePanel?
    private var settingsWindowController: NSWindowController?

    private let windowService = WindowService()
    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private let hotkeyService = HotkeyService()

    /// The SwiftUI view model — kept here so HotkeyService can drive Tab cycling
    private var switcherViewModel: SwitcherViewModel?

    /// Event monitors for Option+Key app bindings
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    /// The hosting view for the current switcher panel content
    private var currentHostingView: NSHostingView<SwitcherWindow>?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[WS] applicationDidFinishLaunching")

        // Screen-recording status detection is an opt-in PermissionFlow module
        // that must be registered before the Settings permission rows read it
        MainActor.assumeIsolated {
            PermissionFlowScreenRecordingStatus.register()
        }

        setupStatusBarItem()
        setupGlobalHotkey()
        setupAppBindingMonitor()

        // Check accessibility permission. Without it the global keyDown
        // monitors (number quick-select, Enter/Escape, Option+Key bindings)
        // receive nothing, so surface the state in the log for diagnosis.
        NSLog("[WS] Accessibility trusted: \(AccessibilityService.isAccessibilityEnabled)")
        if !AccessibilityService.isAccessibilityEnabled {
            AccessibilityService.requestAccessibilityPermission()
        }

        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .switcherSettingsDidChange,
            object: nil
        )

        // Keep the menu bar icon in sync with the "Show menu bar icon" setting
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )

        // Start automatic update checks
        UpdateService.shared.startAutomaticChecks()

        NSLog("[WS] All initialization complete")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Status Bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else {
            NSLog("[WS] statusItem.button is nil")
            return
        }

        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WindowSwitcher") {
            image.isTemplate = true
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        } else {
            button.title = "WS"
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: L10n.showSwitcher, action: #selector(showSwitcherAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: L10n.preferences + "...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quit + " WindowSwitcher", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusItemVisibility()
        NSLog("[WS] Status bar item created")
    }

    @objc private func userDefaultsDidChange() {
        updateStatusItemVisibility()
    }

    private func updateStatusItemVisibility() {
        let show = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if statusItem.isVisible != show {
            statusItem.isVisible = show
        }
    }

    // MARK: - Global Hotkey (Option+Tab)

    private func setupGlobalHotkey() {
        // When Option+Tab is pressed → show the switcher (only if not already visible)
        hotkeyService.onShowSwitcher { [weak self] in
            NSLog("[WS] Option+Tab triggered — showing switcher")
            DispatchQueue.main.async {
                self?.showSwitcher()
            }
        }

        // When Option is released while switcher is visible → confirm selection and hide
        hotkeyService.onConfirmSelection { [weak self] in
            NSLog("[WS] Confirming selection")
            DispatchQueue.main.async {
                self?.confirmAndHideSwitcher()
            }
        }

        // Tab cycling — used by HotkeyService when Option+Tab is held
        hotkeyService.onTabPress { [weak self] in
            NSLog("[WS] Tab — cycling next")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.switcherViewModel?.selectNext()
                }
            }
        }

        // Shift+Tab → cycle to previous item
        hotkeyService.onShiftTabPress { [weak self] in
            NSLog("[WS] Shift+Tab — cycling previous")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.switcherViewModel?.selectPrevious()
                }
            }
        }

        // Provide search active state to HotkeyService via ViewModel
        hotkeyService.isSearchActiveProvider = { [weak self] in
            return MainActor.assumeIsolated {
                self?.switcherViewModel?.isSearchActive ?? false
            }
        }

        // Enter when search inactive → activate search bar via ViewModel
        hotkeyService.onActivateSearch { [weak self] in
            NSLog("[WS] Activating search bar")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.switcherViewModel?.isSearchActive = true
                }
            }
        }

        // Escape when search active → deactivate search bar via ViewModel
        hotkeyService.onDeactivateSearch { [weak self] in
            NSLog("[WS] Deactivating search bar")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.switcherViewModel?.isSearchActive = false
                    self?.switcherViewModel?.searchText = ""
                }
            }
        }

        // Number key 1-9 → jump to Nth item and confirm
        hotkeyService.onNumberPress { [weak self] number in
            NSLog("[WS] Number \(number) — jumping to item")
            DispatchQueue.main.async {
                guard let self = self else { return }
                let index = number - 1 // 1-based to 0-based
                MainActor.assumeIsolated {
                    let items = self.switcherViewModel?.displayItems ?? []
                    NSLog("[WS] Number \(number): index=\(index), totalItems=\(items.count)")
                    if index >= 0 && index < items.count {
                        let item = items[index]
                        NSLog("[WS] Number \(number): selecting item=\(item.displayName), id=\(item.id), isWindow=\(item.isWindow)")
                        self.switcherViewModel?.selectedIndex = index
                        self.confirmAndHideSwitcher()
                    } else {
                        NSLog("[WS] Number \(number): index \(index) out of range (\(items.count) items)")
                    }
                }
            }
        }

        // Escape when search not active → dismiss panel
        hotkeyService.onEscape { [weak self] in
            NSLog("[WS] Escape pressed — dismissing")
            DispatchQueue.main.async {
                self?.hideSwitcher()
            }
        }

        NSLog("[WS] Global hotkey registered")
    }

    // MARK: - App Binding Monitor (Option + Key)

    private func setupAppBindingMonitor() {
        // Remove existing monitors
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }

        // Use a global monitor for Option+Key combinations
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleAppBindingKeyEvent(event)
        }

        // Also add a local monitor for when our app is focused
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleAppBindingKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }

        NSLog("[WS] App binding monitor set up")
    }

    /// Handle Option+Key events for direct app switching.
    /// Returns true if the event was handled.
    @discardableResult
    private func handleAppBindingKeyEvent(_ event: NSEvent) -> Bool {
        // When the switcher panel is active, let HotkeyService handle all keys
        if hotkeyService.isSwitcherActive { return false }

        // Only respond to Option (without Command/Control/Shift)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .option else { return false }

        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else { return false }

        let key = characters.uppercased()

        // Don't handle Tab here — that's for the switcher
        if event.keyCode == 48 { return false } // kVK_Tab = 48

        let settings = settingsStore.load()
        guard let bundleID = settings.bundleID(for: key) else { return false }

        NSLog("[WS] App binding triggered: Option+\(key) -> \(bundleID)")

        DispatchQueue.main.async { [weak self] in
            self?.windowService.activateApp(bundleID: bundleID)
        }

        return true
    }

    @objc private func settingsDidChange() {
        NSLog("[WS] Settings changed, refreshing bindings")
        let settings = settingsStore.load()
        NSLog("[WS] Pinned apps: \(settings.allowedBundleIDs)")
        NSLog("[WS] App bindings: \(settings.appBindings.map { "\($0.triggerKey)->\($0.bundleID)" })")
    }

    // MARK: - Switcher Panel

    @objc private func showSwitcherAction() {
        showSwitcher()
    }

    private func showSwitcher() {
        // If already visible, don't recreate
        if let panel = switcherPanel, panel.isVisible {
            NSLog("[WS] Switcher already visible, ignoring show request")
            return
        }

        if switcherPanel == nil {
            createSwitcherPanel()
        }

        guard let panel = switcherPanel else { return }

        // Create a shared view model so HotkeyService can drive Tab cycling
        let vm = MainActor.assumeIsolated {
            SwitcherViewModel(
                windowService: windowService,
                settingsStore: settingsStore
            )
        }
        self.switcherViewModel = vm

        // Refresh window list BEFORE creating the view
        MainActor.assumeIsolated {
            vm.refreshWindows()
        }

        // Recreate content view each time to refresh window list
        let contentView = SwitcherWindow(
            viewModel: vm,
            onDismiss: { [weak self] in
                self?.hideSwitcher()
            },
            onOpenSettings: { [weak self] in
                self?.hideSwitcher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.openPreferences()
                }
            },
            onItemCountChange: { [weak self] count in
                // Called during a SwiftUI update — defer the frame change
                DispatchQueue.main.async {
                    self?.resizeSwitcherPanel(itemCount: count)
                }
            }
        )

        // Create NSVisualEffectView as the container for blur background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        // Round the corners via maskImage — the sanctioned way for behindWindow
        // blending. Rounding only the layer leaves the blur region square,
        // which shows as opaque corner artifacts (white in light mode).
        visualEffectView.maskImage = Self.roundedCornerMask(radius: 12)
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true

        // Create NSHostingView with SwiftUI content (transparent background)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Remove default opaque background to prevent white border around corners
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.currentHostingView = hostingView

        // Add hostingView as subview of visualEffectView
        visualEffectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])

        panel.contentView = visualEffectView

        // Calculate panel height based on item count
        // Search bar is always visible now (like TabTab)
        let windowCount = MainActor.assumeIsolated { vm.displayItems.count }
        let panelHeight = calculatePanelHeight(itemCount: windowCount)

        NSLog("[WS] panelHeight=\(panelHeight), items=\(windowCount)")

        // Position panel based on user settings
        positionPanel(panel, height: panelHeight)

        // Apply theme setting
        applyTheme(to: panel)

        // Make key window (receives keyboard events) but do NOT activate the app.
        // `.nonactivatingPanel` ensures the app doesn't become active,
        // so other apps remain in the foreground.
        panel.makeKeyAndOrderFront(nil)

        // Notify hotkey service that switcher is now active
        hotkeyService.switcherDidShow()

        NSLog("[WS] Switcher shown (key window, non-activating, \(windowCount) items)")
    }

    /// Calculate panel height based on content.
    /// Search bar is always visible (like TabTab).
    private func calculatePanelHeight(itemCount: Int) -> CGFloat {
        // Search bar: padding-top 10 + content (padding-v 8*2 = 16 + text ~16 = 32) + padding-bottom 4 = 46px
        let searchBarHeight: CGFloat = 46

        // Item: icon 28px + vertical padding 7*2 = 42px
        // Spacing between items: 2px
        let itemHeight: CGFloat = 42
        let itemSpacing: CGFloat = 2

        // List vertical padding: 4px top + 4px bottom = 8px
        let listPadding: CGFloat = 8

        // Bottom bar: padding 8*2 + content ~16px = 32px
        let bottomBarHeight: CGFloat = 32

        let itemsTotal: CGFloat
        if itemCount > 0 {
            itemsTotal = CGFloat(itemCount) * itemHeight + CGFloat(itemCount - 1) * itemSpacing
        } else {
            itemsTotal = 140  // empty state: minHeight 80 + vertical padding 30*2
        }

        let totalHeight = searchBarHeight + listPadding + itemsTotal + bottomBarHeight

        // Clamp to screen bounds
        let maxHeight: CGFloat = min(NSScreen.main?.visibleFrame.height ?? 700, 700)
        return min(max(totalHeight, 150), maxHeight)
    }

    /// Resize the visible panel when the result count changes (e.g. while searching),
    /// keeping the top edge fixed so the search bar doesn't jump
    private func resizeSwitcherPanel(itemCount: Int) {
        guard let panel = switcherPanel, panel.isVisible else { return }
        let height = calculatePanelHeight(itemCount: itemCount)
        var frame = panel.frame
        guard frame.height != height else { return }
        frame.origin.y = frame.maxY - height
        frame.size.height = height

        // Keep the panel inside the screen's visible area when it grows
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if frame.maxY > visible.maxY {
                frame.origin.y = visible.maxY - height
            }
            if frame.minY < visible.minY {
                frame.origin.y = visible.minY
            }
        }

        panel.setFrame(frame, display: true)
    }

    /// Confirm the current selection and hide the switcher
    private func confirmAndHideSwitcher() {
        // Activate the currently selected item
        MainActor.assumeIsolated {
            if let item = switcherViewModel?.selectedItem {
                NSLog("[WS] Confirming: activating item=\(item.displayName), id=\(item.id), isWindow=\(item.isWindow)")
            } else {
                NSLog("[WS] Confirming: no selected item!")
            }
            switcherViewModel?.activateSelectedItem()
        }

        // Small delay to let the activation happen before hiding
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.hideSwitcher()
        }
    }

    private func hideSwitcher() {
        switcherPanel?.orderOut(nil)
        switcherViewModel = nil
        currentHostingView = nil
        hotkeyService.switcherDidHide()
        NSLog("[WS] Switcher hidden")
    }

    private func createSwitcherPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false  // Allow becoming key immediately

        // When the panel loses focus (user clicked elsewhere), close it.
        // hideSwitcher is idempotent, so the resign triggered by our own
        // orderOut/confirm flow is harmless.
        panel.onResignKey = { [weak self] in
            NSLog("[WS] Panel lost focus — dismissing")
            DispatchQueue.main.async {
                self?.hideSwitcher()
            }
        }

        switcherPanel = panel
    }

    /// Position the panel based on user settings (left / center / right) and screen mode (focused / fixed)
    private func positionPanel(_ panel: NSPanel, height: CGFloat) {
        let position = UserDefaults.standard.string(forKey: "panelPosition") ?? "center"
        let screenMode = UserDefaults.standard.string(forKey: "screenMode") ?? "focused"

        let screen: NSScreen
        if screenMode == "fixed" {
            let selectedIndex = UserDefaults.standard.integer(forKey: "selectedScreenIndex")
            let screens = NSScreen.screens
            if selectedIndex >= 0 && selectedIndex < screens.count {
                screen = screens[selectedIndex]
            } else {
                screen = NSScreen.main ?? NSScreen.screens.first!
            }
        } else {
            // "focused" mode: use the screen that currently has the mouse cursor
            let mouseLocation = NSEvent.mouseLocation
            screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
        }

        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 340

        let x: CGFloat
        switch position {
        case "left":
            x = screenFrame.minX + 8
        case "right":
            x = screenFrame.maxX - panelWidth - 8
        default: // center
            x = screenFrame.midX - panelWidth / 2
        }

        let y = screenFrame.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: true)
    }

    /// Apply theme setting to the panel.
    /// "system" leans dark on purpose: the switcher is a transient HUD overlay
    /// and the dark appearance reads best over arbitrary desktop content
    /// (same choice as TabTab / Alfred / Raycast). Explicit "light" still works.
    private func applyTheme(to panel: NSPanel) {
        let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        switch theme {
        case "light":
            panel.appearance = NSAppearance(named: .aqua)
        default: // dark & system
            panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// A stretchable rounded-rect image used to mask the visual effect view
    private static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Preferences

    @objc private func openPreferences() {
        NSLog("[WS] Opening preferences...")

        NSApp.setActivationPolicy(.regular)

        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "WindowSwitcher " + L10n.preferences
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
            window.isReleasedWhenClosed = false

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if self?.settingsWindowController?.window?.isVisible != true {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }

            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Quit

    @objc private func quitApp() {
        NSLog("[WS] Quitting...")

        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }

        NSApp.terminate(nil)
    }
}

// MARK: - Keyboard Shortcuts Extension

extension KeyboardShortcuts.Name {
    static let showSwitcher = Self("showSwitcher", default: .init(.tab, modifiers: [.option]))
}
