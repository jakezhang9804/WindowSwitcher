import AppKit
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var switcherPanel: NSPanel?
    private let windowService = WindowService()
    private let hotkeyService = HotkeyService()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupGlobalHotkey()
        requestAccessibilityPermission()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }
    
    // MARK: - Setup
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Window Switcher")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            self?.showSwitcher()
        }
    }
    
    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("Accessibility permission not granted")
        }
    }
    
    // MARK: - Actions
    
    @objc private func showSwitcher() {
        if switcherPanel == nil {
            createSwitcherPanel()
        }
        
        switcherPanel?.center()
        switcherPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func createSwitcherPanel() {
        let contentView = SwitcherWindow(windowService: windowService) {
            self.hideSwitcher()
        }
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        panel.contentView = NSHostingView(rootView: contentView)
        
        switcherPanel = panel
    }
    
    private func hideSwitcher() {
        switcherPanel?.orderOut(nil)
    }
}

// MARK: - Keyboard Shortcuts Extension

extension KeyboardShortcuts.Name {
    static let showSwitcher = Self("showSwitcher", default: .init(.tab, modifiers: [.option]))
}
