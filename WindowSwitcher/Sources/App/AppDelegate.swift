import AppKit
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var switcherPanel: NSPanel?
    private let windowService = WindowService()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupGlobalHotkey()
        requestAccessibilityPermission()
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Window Switcher")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit WindowSwitcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            self?.toggleSwitcher()
        }
    }
    
    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("⚠️ Accessibility permission not granted")
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
        
        guard let panel = switcherPanel else { return }
        
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
        
        // Recreate content to refresh window list
        updateSwitcherContent()
    }
    
    @objc private func showSettings() {
        // TODO: Implement settings window
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        updateSwitcherContent()
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
