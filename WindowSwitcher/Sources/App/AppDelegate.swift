import AppKit
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem!
    private var switcherPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private let windowService = WindowService()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 applicationDidFinishLaunching called")
        
        setupStatusBarItem()
        setupGlobalHotkey()
        requestAccessibilityPermission()
        
        print("✅ App initialization complete")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 applicationWillTerminate called")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSwitcher()
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Setup
    
    private func setupStatusBarItem() {
        print("📍 Setting up status bar item...")
        
        // 创建状态栏项目
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem.button else {
            print("❌ Failed to get status item button")
            return
        }
        
        // 设置图标
        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Window Switcher") {
            image.isTemplate = true
            button.image = image
            print("✅ Status bar icon set (SF Symbol)")
        } else {
            // 备用方案：使用文字
            button.title = "⧉"
            print("⚠️ Using fallback text for status bar")
        }
        
        // 创建菜单
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
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
        print("📍 Setting up global hotkey...")
        
        // 使用 KeyboardShortcuts 库注册全局快捷键
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            print("🔥 Hotkey triggered!")
            DispatchQueue.main.async {
                self?.toggleSwitcher()
            }
        }
        
        print("✅ Global hotkey registered: Option+Tab")
    }
    
    private func requestAccessibilityPermission() {
        print("📍 Checking accessibility permission...")
        
        // 请求辅助功能权限
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            print("✅ Accessibility permission granted")
        } else {
            print("⚠️ Accessibility permission NOT granted")
            print("   Please enable in System Settings > Privacy & Security > Accessibility")
        }
    }
    
    // MARK: - Actions
    
    private func toggleSwitcher() {
        if let panel = switcherPanel, panel.isVisible {
            hideSwitcher()
        } else {
            showSwitcher()
        }
    }
    
    @objc func showSwitcher() {
        print("📍 showSwitcher called")
        
        // 如果面板不存在，创建它
        if switcherPanel == nil {
            createSwitcherPanel()
        }
        
        guard let panel = switcherPanel else {
            print("❌ Failed to create switcher panel")
            return
        }
        
        // 更新内容（刷新窗口列表）
        updateSwitcherContent()
        
        // 将面板定位到屏幕中央偏上
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2 + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // 显示面板
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("✅ Switcher panel shown")
    }
    
    @objc private func openSettings() {
        print("📍 openSettings called")
        
        if settingsWindow == nil {
            createSettingsWindow()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        print("📍 quitApp called")
        NSApp.terminate(nil)
    }
    
    // MARK: - Window Creation
    
    private func createSwitcherPanel() {
        print("📍 Creating switcher panel...")
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        // 面板配置
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .utilityWindow
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
        print("✅ Switcher hidden")
    }
    
    private func createSettingsWindow() {
        print("📍 Creating settings window...")
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "WindowSwitcher Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        
        settingsWindow = window
        
        print("✅ Settings window created")
    }
}

// MARK: - Keyboard Shortcuts Extension

extension KeyboardShortcuts.Name {
    static let showSwitcher = Self("showSwitcher", default: .init(.tab, modifiers: [.option]))
}
