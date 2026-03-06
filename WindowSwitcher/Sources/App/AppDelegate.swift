import AppKit
import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    /// 必须用 strong reference 保持 statusItem 存活
    private var statusItem: NSStatusItem!
    private var switcherPanel: NSPanel?
    private var settingsWindowController: NSWindowController?
    private let windowService = WindowService()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupGlobalHotkey()
        checkAccessibilityPermission()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
    
    // MARK: - Status Bar
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem.button else { return }
        
        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WindowSwitcher") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "WS"
        }
        
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcherAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(.separator())
        
        let settingsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: "Quit WindowSwitcher", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    // MARK: - Global Hotkey
    
    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleSwitcher()
            }
        }
    }
    
    // MARK: - Accessibility
    
    private func checkAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let _ = AXIsProcessTrustedWithOptions(options)
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
        
        // 每次显示时刷新内容
        let contentView = SwitcherWindow(windowService: windowService, onDismiss: { [weak self] in
            self?.hideSwitcher()
        }, onOpenSettings: { [weak self] in
            self?.hideSwitcher()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.openPreferences()
            }
        })
        panel.contentView = NSHostingView(rootView: contentView)
        
        // 定位到屏幕左侧（与 TabTab 一致）
        positionPanelOnLeft(panel)
        
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func hideSwitcher() {
        switcherPanel?.orderOut(nil)
    }
    
    private func createSwitcherPanel() {
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 600
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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
        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 480))
            window.center()
            window.isReleasedWhenClosed = false
            
            settingsWindowController = NSWindowController(window: window)
        }
        
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Quit
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Keyboard Shortcuts

extension KeyboardShortcuts.Name {
    static let showSwitcher = Self("showSwitcher", default: .init(.tab, modifiers: [.option]))
}
