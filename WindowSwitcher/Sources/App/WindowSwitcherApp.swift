import AppKit

// 使用传统的 AppKit 方式启动应用，而非 SwiftUI App 协议
// 这是 TabTab 等菜单栏应用的标准做法

@main
struct WindowSwitcherApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // 设置为 accessory 类型，不显示在 Dock 中
        app.setActivationPolicy(.accessory)
        
        app.run()
    }
}
