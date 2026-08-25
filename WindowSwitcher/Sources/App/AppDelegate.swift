import AppKit
import SwiftUI
import AppSwitcherKit
import PermissionFlowScreenRecordingStatus

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Must keep a strong reference to statusItem, otherwise the menu bar icon will disappear
    private var statusItem: NSStatusItem!
    private var switcherPanel: KeyablePanel?
    private var settingsWindowController: NSWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?

    private let windowService = WindowService()
    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private let hotkeyService = HotkeyService()

    /// Accessibility can be granted while the app is already running. Retry the
    /// event tap briefly so the hotkey starts working without a relaunch.
    private var permissionRetryTimer: Timer?

    /// The SwiftUI view model — kept here so HotkeyService can drive Tab cycling
    private var switcherViewModel: SwitcherViewModel?

    /// The hosting view for the current switcher panel content
    private var currentHostingView: NSHostingView<SwitcherWindow>?

    /// Search temporarily activates this accessory app for IME input. Keep the
    /// prior foreground app so cancelling the switcher can return focus cleanly.
    private var previousFrontmostApplication: NSRunningApplication?

    /// True while a confirm is in flight. Guards against a double-confirm when a
    /// number-key press and a modifier-release land almost simultaneously (each
    /// would otherwise fire its own activate/hide, racing focus and possibly
    /// activating different items), and lets onResignKey skip its redundant hide.
    private var isConfirming = false

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

        // CGEventTap enables Cmd+Tab takeover and reliable modifier-release
        // detection. It shares the Accessibility permission already required
        // for enumerating and activating windows.
        hotkeyService.startEventTap()
        scheduleEventTapRetryIfNeeded()

        // Check accessibility permission. Without it the global keyDown
        // monitors (number quick-select, Enter/Escape, Option+Key bindings)
        // receive nothing, so surface the state in the log for diagnosis.
        NSLog("[WS] Accessibility trusted: \(AccessibilityService.isAccessibilityEnabled)")
        if !AccessibilityService.isAccessibilityEnabled {
            if !UserDefaults.standard.bool(forKey: "hasPresentedPermissionSetup") {
                UserDefaults.standard.set(true, forKey: "hasPresentedPermissionSetup")
                AccessibilityService.requestAccessibilityPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.openPreferences()
                }
            }
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

        // Dev hooks: allow driving the UI from the command line so visual
        // states can be opened and screenshotted without keyboard input
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openPreferences),
            name: Notification.Name("com.windowswitcher.debug.openPreferences"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showSwitcherAction),
            name: Notification.Name("com.windowswitcher.debug.showSwitcher"),
            object: nil
        )

        // Start automatic update checks
        UpdateService.shared.startAutomaticChecks()

        NSLog("[WS] All initialization complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        hotkeyService.stopEventTap()
        hotkeyService.switcherDidHide()
        UpdateService.shared.stopAutomaticChecks()
        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
            self.settingsWindowCloseObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard AccessibilityService.isAccessibilityEnabled,
              !hotkeyService.isEventTapActive else { return }
        hotkeyService.stopEventTap()
        hotkeyService.startEventTap()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openPreferences() }
        return true
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
            NSLog("[WS] Switcher hotkey triggered — showing switcher")
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

        // Arrow keys — list navigation + per-app window drill-down (byApp grouping)
        hotkeyService.onUpArrow { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.switcherViewModel?.moveUp() } }
        }
        hotkeyService.onDownArrow { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.switcherViewModel?.moveDown() } }
        }
        hotkeyService.onRightArrow { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.switcherViewModel?.enterSecondary() } }
        }
        hotkeyService.onLeftArrow { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.switcherViewModel?.exitSecondary() } }
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

        // Number key 1-9 → jump to Nth item in the CURRENT list and confirm
        hotkeyService.onNumberPress { [weak self] number in
            NSLog("[WS] Number \(number) — jumping to item")
            DispatchQueue.main.async {
                guard let self = self else { return }
                let index = number - 1 // 1-based to 0-based
                MainActor.assumeIsolated {
                    let items = self.switcherViewModel?.displayedItems ?? []
                    NSLog("[WS] Number \(number): index=\(index), totalItems=\(items.count)")
                    if index >= 0 && index < items.count {
                        NSLog("[WS] Number \(number): selecting valid item")
                        self.switcherViewModel?.selectDisplayed(index)
                        self.confirmAndHideSwitcher()
                    } else {
                        NSLog("[WS] Number \(number): index \(index) out of range (\(items.count) items)")
                    }
                }
            }
        }

        // Escape follows the visible hierarchy: search is handled by
        // HotkeyService, then a window drill-down backs out, and only the
        // top-level list dismisses.
        hotkeyService.onEscape { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.switcherViewModel?.secondaryActive == true {
                    NSLog("[WS] Escape pressed — leaving secondary list")
                    self.switcherViewModel?.exitSecondary()
                } else {
                    NSLog("[WS] Escape pressed — dismissing")
                    self.hideSwitcher()
                }
            }
        }

        NSLog("[WS] Global hotkey registered")
    }

    private func scheduleEventTapRetryIfNeeded() {
        permissionRetryTimer?.invalidate()
        guard !hotkeyService.isEventTapActive else { return }

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard AccessibilityService.isAccessibilityEnabled else { return }

            self.hotkeyService.startEventTap()
            if self.hotkeyService.isEventTapActive {
                timer.invalidate()
                self.permissionRetryTimer = nil
                NSLog("[WS][Hotkey] Event tap started after permission grant")
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        permissionRetryTimer = timer
    }

    @objc private func settingsDidChange() {
        NSLog("[WS] Settings changed")
        let settings = settingsStore.load()
        NSLog("[WS] App groups: \(settings.appGroups.map { $0.name })")
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

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApplication = frontmost
        }

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

        let layout = switcherLayout

        // Recreate content view each time to refresh window list
        let contentView = SwitcherWindow(
            viewModel: vm,
            layout: layout,
            onConfirm: { [weak self] in
                self?.confirmAndHideSwitcher()
            },
            onOpenSettings: { [weak self] in
                self?.hideSwitcher(restorePreviousApp: false)
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
        // (the centered strip uses the larger radius of the native switcher)
        let cornerRadius: CGFloat = layout == .strip ? 22 : 16
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        // Mask the material itself as well as its layer so both composition
        // modes keep clean antialiased corners without opaque edge artifacts.
        visualEffectView.maskImage = Self.roundedCornerMask(radius: cornerRadius)
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
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

        // Size and position the panel for the chosen layout
        let windowCount = MainActor.assumeIsolated { vm.displayItems.count }
        if layout == .strip {
            positionStripPanel(panel, itemCount: windowCount, searchActive: false)
        } else {
            let panelHeight = calculatePanelHeight(itemCount: windowCount)
            positionPanel(panel, height: panelHeight)
        }

        NSLog("[WS] layout=\(layout), items=\(windowCount)")

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

        let itemHeight = SwitcherWindow.listRowHeight
        let itemSpacing = SwitcherWindow.listRowSpacing

        // Bottom bar: padding 8*2 + content ~16px = 32px
        let bottomBarHeight: CGFloat = 32

        // Cap the list at 9 visible rows — matching SwitcherWindow's
        // `listContentHeight`; extra rows scroll inside the fixed panel.
        let visibleCount = min(itemCount, SwitcherWindow.listMaxVisibleRows)
        let itemsTotal: CGFloat
        if itemCount > 0 {
            itemsTotal = CGFloat(visibleCount) * itemHeight + CGFloat(visibleCount - 1) * itemSpacing
        } else {
            itemsTotal = 140  // empty state: minHeight 80 + vertical padding 30*2
        }

        let totalHeight = searchBarHeight + itemsTotal + bottomBarHeight

        // Clamp to screen bounds
        let maxHeight: CGFloat = min(NSScreen.main?.visibleFrame.height ?? 700, 700)
        return min(max(totalHeight, 150), maxHeight)
    }

    /// Panel height for the drilled-in per-app window list: back header (40) +
    /// capped rows + vertical padding (12), matching SwitcherWindow.secondaryBody.
    private func calculateSecondaryHeight(itemCount: Int) -> CGFloat {
        let total = 40 + SwitcherWindow.listHeight(for: itemCount) + 12
        let maxHeight = min(NSScreen.main?.visibleFrame.height ?? 700, 700)
        return min(max(total, 120), maxHeight)
    }

    /// Resize the visible panel when the displayed list changes (search, drill-in,
    /// item count), keeping the list top edge fixed so it doesn't jump.
    private func resizeSwitcherPanel(itemCount: Int) {
        guard let panel = switcherPanel, panel.isVisible else { return }

        let (secondary, searchActive, count) = MainActor.assumeIsolated {
            (switcherViewModel?.secondaryActive ?? false,
             switcherViewModel?.isSearchActive ?? false,
             switcherViewModel?.displayedItems.count ?? itemCount)
        }

        // Drilled into an app's windows → a 340-wide list, positioned like the
        // list layout (left/right edge, or centered when the layout is center).
        if secondary {
            positionPanel(panel, height: calculateSecondaryHeight(itemCount: count))
            return
        }

        if switcherLayout == .strip {
            positionStripPanel(panel, itemCount: count, searchActive: searchActive)
            return
        }

        let height = calculatePanelHeight(itemCount: count)
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

    /// Confirm the current selection and hide the switcher.
    ///
    /// Order matters: the panel is a key window, so we relinquish it FIRST
    /// (order out + tear down), THEN activate the target. Activating before the
    /// panel gives up focus made the window server race the panel's order-out
    /// and sometimes hand focus back to the previously-frontmost app — an
    /// intermittent "didn't switch". Single-shot via `isConfirming` so a
    /// near-simultaneous number-key + modifier-release can't double-fire.
    private func confirmAndHideSwitcher() {
        MainActor.assumeIsolated {
            guard !isConfirming else {
                NSLog("[WS] Confirm ignored — already confirming")
                return
            }
            isConfirming = true

            guard let viewModel = switcherViewModel, viewModel.selectedItem != nil else {
                NSLog("[WS] Confirm ignored — no selected item")
                isConfirming = false
                return
            }

            if let item = viewModel.selectedItem {
                NSLog("[WS] Confirming: activating id=\(item.id), secondary=\(switcherViewModel?.secondaryActive ?? false)")
            }

            // 1) Relinquish focus and fully tear down the panel session.
            switcherPanel?.orderOut(nil)
            switcherViewModel = nil
            currentHostingView = nil
            switcherPanel?.contentView = nil
            hotkeyService.switcherDidHide()

            // 2) Activate the resolved target only after no switcher window or
            // input monitor can race to reclaim focus.
            previousFrontmostApplication = nil
            viewModel.activateResolvedSelection()
            isConfirming = false
            NSLog("[WS] Switcher hidden (after confirm)")
        }
    }

    private func hideSwitcher(restorePreviousApp: Bool = true) {
        switcherPanel?.orderOut(nil)
        switcherViewModel = nil
        currentHostingView = nil
        switcherPanel?.contentView = nil
        hotkeyService.switcherDidHide()

        if restorePreviousApp,
           NSApp.isActive,
           let previous = previousFrontmostApplication,
           !previous.isTerminated,
           previous.bundleIdentifier != Bundle.main.bundleIdentifier {
            previous.activate()
        }
        previousFrontmostApplication = nil
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
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false  // Allow becoming key immediately

        // When the panel loses focus (user clicked elsewhere), close it.
        // During a confirm we order the panel out ourselves and activate the
        // target — skip the redundant hide so it doesn't churn focus mid-switch.
        panel.onResignKey = { [weak self] in
            guard let self = self else { return }
            if self.isConfirming { return }
            NSLog("[WS] Panel lost focus — dismissing")
            DispatchQueue.main.async {
                self.hideSwitcher()
            }
        }

        switcherPanel = panel
    }

    /// The layout for the switcher panel: the "center" position mirrors the
    /// native Cmd+Tab switcher (horizontal icon strip); left/right keep the
    /// vertical edge panel.
    private var switcherLayout: SwitcherLayout {
        let position = UserDefaults.standard.string(forKey: "panelPosition") ?? "center"
        return position == "center" ? .strip : .list
    }

    /// The screen the panel should appear on (focused / fixed setting)
    private func targetScreen() -> NSScreen {
        let screenMode = UserDefaults.standard.string(forKey: "screenMode") ?? "focused"
        if screenMode == "fixed" {
            let selectedDisplayID = UserDefaults.standard.string(forKey: "selectedScreenID")
            if let screen = NSScreen.screen(withPersistentDisplayID: selectedDisplayID) {
                return screen
            }

            // Legacy installations only persisted the array index. Use it once
            // when no UUID exists; the settings page migrates it on first open.
            let selectedIndex = UserDefaults.standard.integer(forKey: "selectedScreenIndex")
            let screens = NSScreen.screens
            if (selectedDisplayID ?? "").isEmpty,
               selectedIndex >= 0 && selectedIndex < screens.count {
                return screens[selectedIndex]
            }
            return NSScreen.main ?? NSScreen.screens.first!
        }
        // "focused" mode: use the screen that currently has the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first!
    }

    /// Size and center the horizontal strip panel, native-switcher style:
    /// width follows the item count up to the screen edge, centered on screen.
    private func positionStripPanel(_ panel: NSPanel, itemCount: Int, searchActive: Bool) {
        let screen = targetScreen()
        let visible = screen.visibleFrame

        let contentWidth = CGFloat(max(itemCount, 1)) * SwitcherWindow.stripCellSize
            + CGFloat(max(itemCount - 1, 0)) * SwitcherWindow.stripSpacing
            + SwitcherWindow.stripHorizontalPadding * 2
        let width = min(max(contentWidth, 280), visible.width - 120)

        // 14pt outer padding + 82pt cell + 6pt spacing + 22pt caption.
        var height: CGFloat = 138
        if searchActive { height += 52 }
        if itemCount == 0 { height = 176 }

        let x = visible.midX - width / 2
        let y = visible.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    /// Position the list panel based on user settings (left / right) and screen mode (focused / fixed)
    private func positionPanel(_ panel: NSPanel, height: CGFloat) {
        let position = UserDefaults.standard.string(forKey: "panelPosition") ?? "center"
        let screen = targetScreen()
        let screenFrame = screen.visibleFrame
        let panelWidth = SwitcherWindow.listWidth

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

    /// Apply the selected theme. Leaving `appearance` nil lets AppKit follow the
    /// current system appearance and respond to changes while the app is running.
    private func applyTheme(to panel: NSPanel) {
        let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        switch theme {
        case "light":
            panel.appearance = NSAppearance(named: .aqua)
        case "dark":
            panel.appearance = NSAppearance(named: .darkAqua)
        default:
            panel.appearance = nil
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
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 800, height: 620))
            window.minSize = NSSize(width: 760, height: 540)
            window.collectionBehavior = [.moveToActiveSpace]
            window.tabbingMode = .disallowed
            window.titlebarSeparatorStyle = .line
            window.center()
            window.isReleasedWhenClosed = false

            settingsWindowCloseObserver = NotificationCenter.default.addObserver(
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

        // Displays may have been rearranged/disconnected since the window was
        // last positioned — recenter if it no longer lands on an active screen
        if let window = settingsWindowController?.window,
           !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)

        // Start with no field focused so the settings hierarchy remains stable.
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController?.window?.makeFirstResponder(nil)
        }
    }

    // MARK: - Quit

    @objc private func quitApp() {
        NSLog("[WS] Quitting...")
        NSApp.terminate(nil)
    }
}
