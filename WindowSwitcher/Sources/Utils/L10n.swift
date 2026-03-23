import Foundation

/// Simple localization utility that supports Chinese and English.
/// Detects the system language at runtime and returns the appropriate string.
enum L10n {
    /// Whether the current system language is Chinese (Simplified or Traditional)
    static let isChinese: Bool = {
        guard let lang = Locale.preferredLanguages.first else { return false }
        return lang.hasPrefix("zh")
    }()

    // MARK: - Switcher Panel

    static let searchPlaceholder = isChinese ? "搜索窗口和应用…" : "Search windows and apps..."
    static let searchInactivePlaceholder = isChinese ? "按回车搜索…" : "Press Enter to search..."
    static let windowCount = isChinese ? "个窗口" : " windows"
    static func windowCountText(_ count: Int) -> String {
        isChinese ? "\(count) 个窗口" : "\(count) window\(count == 1 ? "" : "s")"
    }
    static let poweredByManus = isChinese ? "基于 Manus 开发" : "Powered by Manus"
    static let settings = isChinese ? "设置" : "Settings"
    static let noResults = isChinese ? "没有找到匹配的窗口" : "No matching windows found"
    static let noResultsHint = isChinese ? "尝试其他搜索词" : "Try a different search term"
    static let noWindows = isChinese ? "没有打开的窗口" : "No open windows"

    // MARK: - Settings: Tabs

    static let preferencesTab = isChinese ? "偏好设置" : "Preferences"
    static let hotkeysTab = isChinese ? "快捷键" : "Hotkeys"
    static let aboutTab = isChinese ? "关于" : "About"

    // MARK: - Settings: Permissions

    static let permissionsTitle = isChinese ? "权限" : "Permissions"
    static let permissionsDescription = isChinese
        ? "WindowSwitcher 需要以下权限才能正常工作："
        : "WindowSwitcher needs the following permissions to work properly:"
    static let accessibilityTitle = isChinese ? "辅助功能" : "Accessibility"
    static let accessibilityDescription = isChinese
        ? "用于激活和切换窗口"
        : "Required to activate and raise windows"
    static let screenRecordingTitle = isChinese ? "屏幕录制" : "Screen Recording"
    static let screenRecordingDescription = isChinese
        ? "用于读取窗口标题以进行搜索和显示"
        : "Required to read window titles for search and display"
    static let permissionsRestart = isChinese
        ? "授权后可能需要重新启动应用。"
        : "After granting permissions, you may need to restart the app."
    static let openSettings = isChinese ? "打开设置" : "Open Settings"

    // MARK: - Settings: General

    static let generalTitle = isChinese ? "通用" : "General"
    static let showMenuBarIcon = isChinese ? "显示菜单栏图标" : "Show menu bar icon"
    static let startAtLogin = isChinese ? "开机启动" : "Start at login"

    // MARK: - Settings: Appearance

    static let appearanceTitle = isChinese ? "外观" : "Appearance"
    static let themeTitle = isChinese ? "主题" : "Theme"
    static let themeSystem = isChinese ? "跟随系统" : "System"
    static let themeLight = isChinese ? "浅色" : "Light"
    static let themeDark = isChinese ? "深色" : "Dark"
    static let panelPositionTitle = isChinese ? "面板位置" : "Panel Position"
    static let positionLeft = isChinese ? "左" : "Left"
    static let positionCenter = isChinese ? "中" : "Center"
    static let positionRight = isChinese ? "右" : "Right"

    // MARK: - Settings: Show on Screen

    static let showOnScreenTitle = isChinese ? "显示屏幕" : "Show on screen"
    static let screenModeFocused = isChinese ? "当前聚焦屏幕" : "Focused screen"
    static let screenModeFixed = isChinese ? "固定屏幕" : "Fixed screen"
    static let fixedScreenDescription = isChinese
        ? "选择切换面板始终显示在哪个屏幕上。"
        : "Choose which screen the switcher panel always appears on."
    static func screensDetected(_ count: Int) -> String {
        isChinese ? "检测到 \(count) 个屏幕" : "\(count) screen\(count == 1 ? "" : "s") detected"
    }

    // MARK: - Settings: Pinned Apps

    static let pinnedAppsTitle = isChinese ? "固定应用" : "Pinned Apps"
    static let pinnedAppsDescription = isChinese
        ? "选择要固定的应用。切换器将只在固定的应用之间循环。可以为每个应用分配触发键（A-Z, 0-9），通过 Option + 键快速切换到指定应用。"
        : "Select apps to pin. The switcher will only cycle through pinned apps. Optionally assign a trigger key (A-Z, 0-9) to quickly switch to a specific app via Option + Key."
    static let searchAppsPlaceholder = isChinese ? "搜索已安装的应用…" : "Search installed apps..."
    static let noAppsFound = isChinese ? "未找到应用" : "No apps found"

    // MARK: - Settings: Hotkeys

    static let keyboardShortcutsTitle = isChinese ? "键盘快捷键" : "Keyboard Shortcuts"
    static let showSwitcherLabel = isChinese ? "显示切换器：" : "Show Switcher:"
    static let hotkeysTip1 = isChinese
        ? "按下快捷键可快速切换窗口。"
        : "Press the shortcut key to quickly switch between windows."
    static let hotkeysTip2 = isChinese
        ? "你还可以在偏好设置 > 固定应用中为每个应用分配触发键。使用 Option + [键] 直接切换到指定应用。"
        : "You can also assign per-app trigger keys in Preferences > Pinned Apps. Use Option + [Key] to switch directly to a specific app."
    static let tipsTitle = isChinese ? "提示" : "Tips"

    // MARK: - Settings: About

    static let aboutDescription = isChinese
        ? "一个快速、原生的 macOS 窗口切换器"
        : "A fast and native window switcher for macOS"
    static let checkForUpdates = isChinese ? "检查更新" : "Check for Updates"
    static let checkingForUpdates = isChinese ? "正在检查更新…" : "Checking for updates..."
    static func updateAvailable(_ version: String) -> String {
        isChinese ? "版本 \(version) 可用！" : "Version \(version) is available!"
    }
    static let downloadUpdate = isChinese ? "下载更新" : "Download Update"
    static let skipVersion = isChinese ? "跳过此版本" : "Skip This Version"

    // MARK: - Menu Bar

    static let showSwitcher = isChinese ? "显示切换器" : "Show Switcher"
    static let preferences = isChinese ? "偏好设置" : "Preferences"
    static let quit = isChinese ? "退出" : "Quit"
}
