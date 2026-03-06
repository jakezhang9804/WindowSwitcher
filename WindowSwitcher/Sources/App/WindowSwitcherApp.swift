import AppKit

/// 应用入口
/// 使用传统 AppKit 方式启动，确保 AppDelegate 正确初始化
/// 参考 TabTab 的启动方式
@main
enum WindowSwitcherApp {
    static func main() {
        let app = NSApplication.shared
        
        // delegate 必须用局部变量持有，否则可能被释放
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // 不显示在 Dock 中，仅菜单栏图标
        app.setActivationPolicy(.accessory)
        
        // 启动主事件循环（此调用不会返回）
        app.run()
    }
}
