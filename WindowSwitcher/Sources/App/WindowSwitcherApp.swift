import AppKit

/// 应用入口
/// NSApplication.delegate 是 weak 引用，必须用 static 变量持有 AppDelegate
/// 防止被 ARC 释放
@main
enum WindowSwitcherApp {
    /// 用 static 变量持有 delegate，防止被 ARC 释放
    static let delegate = AppDelegate()
    
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        
        // 不显示在 Dock 中，仅菜单栏图标
        app.setActivationPolicy(.accessory)
        
        // 启动主事件循环（此调用不会返回）
        app.run()
    }
}
