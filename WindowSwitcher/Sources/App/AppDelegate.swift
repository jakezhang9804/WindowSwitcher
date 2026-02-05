import AppKit
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem!
    private var switcherPanel: NSPanel?
    private let windowService = WindowService()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we run on main thread
        DispatchQueue.main.async { [weak self] in
            self?.setupStatusBarItem()
            self?.setupGlobalHotkey()
            self?.requestAccessibilityPermission()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSwitcher()
        return true
    }
    
    // MARK: - Setup
    
    private func setupStatusBarItem() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem.button else {
            print("❌ Failed to create status bar button")
            return
        }
        
        // Set icon
        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Window Switcher") {
            image.isTemplate = true
            button.image = image
        } else {
            // Fallback: use text if symbol not available
            button.title = "WS"
        }
        
        // Create menu
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit WindowSwitcher", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        
        print("✅ Status bar item created successfully")
    }
    
    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleSwitcher()
            }
        }
        print("✅ Global hotkey registered: Option+Tab")
    }
    
    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("⚠️ Accessibility permission not granted - please enable in System Settings")
        } else {
            print("✅ Accessibility permission granted")
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleSwitcher() {
        if let panel = switcherPanel, panel.isVisible {
            hideSwitcher()
        } else {
            showSwitcher()
        }
    }
    
    @objc private func showSwitcher() {
        // Create panel if needed
        if switcherPanel == nil {
            createSwitcherPanel()
        }
        
        guard let panel = switcherPanel else {
            print("❌ Failed to create switcher panel")
            return
        }
        
        // Recreate content to refresh window list
        updateSwitcherContent()
        
        // Position panel in center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2 + 100 // Slightly above center
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Show panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("✅ Switcher shown")
    }
    
    @objc private func showSettings() {
        // Open settings window using SwiftUI Settings scene
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func createSwitcherPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        // Panel configuration
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // We handle shadow in SwiftUI
        panel.animationBehavior = .utilityWindow
        
        // Handle clicks outside the panel
        panel.hidesOnDeactivate = true
        
        switcherPanel = panel
        
        print("✅ Switcher panel created")
    }
    
    private func updateSwitcherContent() {
        guard let panel = switcherPanel else { return }
        
        let contentView = SwitcherWindow(windowService: windowService) { [weak self] in
            self?.hideSwitcher()
        }
        
        panel.contentView = NSHostingView(rootView: contentView)
    }
    
    private func hideSwitcher() {
        switcherPanel?.orderOut(nil)
    }
}

// MARK: - Keyboard Shortcuts Extension

extension KeyboardShortcuts.Name {
    static let showSwitcher = Self("showSwitcher", default: .init(.tab, modifiers: [.option]))
}
