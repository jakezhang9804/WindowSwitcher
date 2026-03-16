import AppKit
import SwiftUI
import KeyboardShortcuts
import AppSwitcherKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Must keep a strong reference to statusItem, otherwise the menu bar icon will disappear
    private var statusItem: NSStatusItem!
    private var switcherPanel: NSPanel?
    private var settingsWindowController: NSWindowController?

    private let windowService = WindowService()
    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private let hotkeyService = HotkeyService()

    /// Event monitors for Option+Key app bindings
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[WS] applicationDidFinishLaunching")

        setupStatusBarItem()
        setupGlobalHotkey()
        setupAppBindingMonitor()

        // Check accessibility permission
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

        let showItem = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcherAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit WindowSwitcher", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        NSLog("[WS] Status bar item created")
    }

    // MARK: - Global Hotkey (Show Switcher)

    private func setupGlobalHotkey() {
        hotkeyService.onShowSwitcher { [weak self] in
            NSLog("[WS] Hotkey triggered")
            DispatchQueue.main.async {
                self?.toggleSwitcher()
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
        // Only respond to Option (without Command/Control/Shift)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .option else { return false }

        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else { return false }

        let key = characters.uppercased()

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

    private func toggleSwitcher() {
        if let panel = switcherPanel, panel.isVisible {
            hideSwitcher()
        } else {
            showSwitcher()
        }
    }

    @objc private func showSwitcherAction() {
        showSwitcher()
    }

    private func showSwitcher() {
        if switcherPanel == nil {
            createSwitcherPanel()
        }

        guard let panel = switcherPanel else { return }

        // Recreate content view each time to refresh window list
        let contentView = SwitcherWindow(
            windowService: windowService,
            settingsStore: settingsStore,
            onDismiss: { [weak self] in
                self?.hideSwitcher()
            },
            onOpenSettings: { [weak self] in
                self?.hideSwitcher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.openPreferences()
                }
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)
        positionPanelOnLeft(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSLog("[WS] Switcher shown")
    }

    private func hideSwitcher() {
        switcherPanel?.orderOut(nil)
    }

    private func createSwitcherPanel() {
        let panel = NSPanel(
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
        panel.hidesOnDeactivate = true

        switcherPanel = panel
    }

    private func positionPanelOnLeft(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = min(screenFrame.height - 40, 700)
        let x = screenFrame.minX + 8
        let y = screenFrame.midY - panelHeight / 2

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    // MARK: - Preferences

    @objc private func openPreferences() {
        NSLog("[WS] Opening preferences...")

        NSApp.setActivationPolicy(.regular)

        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "WindowSwitcher Preferences"
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
