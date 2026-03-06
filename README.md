# WindowSwitcher

一个 macOS 原生窗口切换器应用，灵感来源于 TabTab。

## 功能特性

- **窗口切换**: 在 Mac 上所有打开的窗口之间快速切换
- **全局搜索**: 搜索所有窗口，支持按应用名称、窗口标题搜索
- **键盘优先**: 专为无鼠标导航设计，可自定义快捷键
- **原生设计**: 与 macOS 无缝集成，提供原生外观和感觉

## 技术栈

| 技术 | 用途 |
|------|------|
| **Swift 5.9+** | 主要开发语言 |
| **SwiftUI** | UI 框架 |
| **AppKit** | 系统集成 |
| **Accessibility API** | 窗口信息获取 |

## 第三方依赖

| 库 | 用途 | 来源 |
|----|------|------|
| **KeyboardShortcuts** | 全局快捷键管理 | [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| **Sparkle** | 应用自动更新 | [sparkle-project.org](https://sparkle-project.org/) |

## 系统要求

- macOS 14.0+
- 支持 Intel 和 Apple Silicon

## 项目结构

```
WindowSwitcher/
├── Sources/
│   ├── App/                    # 应用入口和配置
│   │   ├── WindowSwitcherApp.swift
│   │   └── AppDelegate.swift
│   ├── Views/                  # SwiftUI 视图
│   │   ├── SwitcherWindow.swift
│   │   ├── SearchField.swift
│   │   ├── ResultsList.swift
│   │   ├── ResultItem.swift
│   │   └── SettingsView.swift
│   ├── ViewModels/             # 视图模型
│   │   ├── SwitcherViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Services/               # 服务层
│   │   ├── WindowService.swift
│   │   ├── AccessibilityService.swift
│   │   └── HotkeyService.swift
│   ├── Models/                 # 数据模型
│   │   ├── WindowInfo.swift
│   │   └── AppInfo.swift
│   └── Utils/                  # 工具类
│       └── Extensions.swift
├── Resources/
│   ├── Info.plist
│   └── Localizable.strings
└── Assets.xcassets/
    └── AppIcon.appiconset/
```

## 核心 API

### Accessibility API

```swift
// 获取窗口列表
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
```

### 窗口激活

```swift
// 使用 AXUIElement 激活窗口
let app = AXUIElementCreateApplication(pid)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
```

## 开发指南

1. 克隆仓库
2. 使用 Xcode 15+ 打开 `WindowSwitcher.xcodeproj`
3. 在 Xcode 中添加 Swift Package 依赖
4. 构建并运行

## 许可证

MIT License
