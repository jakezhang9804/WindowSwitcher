import AppKit
import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    /// 必须用 strong reference 保持 statusItem 存活，否则菜单栏图标会消失
    private var statusItem: NSStatusItem!
    private var switcherPanel: NSPanel?
    private var settingsWindowController: NSWindowController?
    private let windowService = WindowService()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[WS] ✅ applicationDidFinishLaunching")
        
        setupStatusBarItem()
        setupGlobalHotkey()
        checkAccessibilityPermission()
        
        NSLog("[WS] ✅ All initialization complete")
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
    
    // MARK: - Status Bar (常驻菜单栏图标)
    
    private func setupStatusBarItem() {
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem.button else {
            NSLog("[WS] ❌ statusItem.button is nil")
            return
        }
        
        // 设置图标
        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WindowSwitcher") {
            image.isTemplate = true
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        } else {
            button.title = "WS"
        }
        
        // 构建菜单
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
        
        NSLog("[WS] ✅ Status bar item created")
    }
    
    // MARK: - Global Hotkey
    
    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .showSwitcher) { [weak self] in
            NSLog("[WS] 🔑 Hotkey triggered")
            DispatchQueue.main.async {
                self?.toggleSwitcher()
            }
        }
        NSLog("[WS] ✅ Global hotkey registered (Option+Tab)")
    }
    
    // MARK: - Accessibility Permission
    
    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        NSLog("[WS] Accessibility trusted: \(trusted)")
        
        if !trusted {
            // 弹出系统权限请求对话框
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as NSDictionary
            AXIsProcessTrustedWithOptions(options)
            NSLog("[WS] ⚠️ Accessibility permission requested")
        }
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
        
        // 每次显示时重新创建内容视图以刷新窗口列表
        let contentView = SwitcherWindow(
            windowService: windowService,
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
        
        NSLog("[WS] ✅ Switcher shown")
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
        
        // 打开设置时切换到 regular 模式以显示窗口
        NSApp.setActivationPolicy(.regular)
        
        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "WindowSwitcher Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 480))
            window.center()
            window.isReleasedWhenClosed = false
            
            // 当设置窗口关闭时，切回 accessory 模式
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                // 延迟切回，避免闪烁
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
        NSApp.terminate(nil)
    }
}

// MARK: - Keyboard Shortcuts Extension

extension KeyboardShortcuts.Name {
    static let showSwitcher = Self("showSwitcher", default: .init(.tab, modifiers: [.option]))
}
