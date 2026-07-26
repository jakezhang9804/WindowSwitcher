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
    static let drillHint = isChinese ? "查看窗口" : "Windows"

    // MARK: - App Groups

    static func groupMembers(_ count: Int) -> String {
        isChinese ? "\(count) 个应用" : "\(count) app\(count == 1 ? "" : "s")"
    }
    static let appGroupsTitle = isChinese ? "应用分组（屏幕录制）" : "App Groups (Screen Recording)"
    static let appGroupsDescription = isChinese
        ? "把某块屏幕上当前摆好的窗口录制成一个分组。切换到分组时会启动其中的应用、把每个窗口还原到录制时的位置和大小并全部前置。分组里的应用不会再单独出现在切换器中。"
        : "Record the windows currently arranged on a screen as one group. Switching to it launches those apps, restores each window to its recorded position and size, and brings them forward. Apps in a group no longer appear standalone in the switcher."
    static let groupRecordNew = isChinese ? "录制此屏幕为新分组" : "Record screen as new group"
    static let groupUpdateRecording = isChinese ? "更新录制" : "Re-record"
    static let deleteGroup = isChinese ? "删除" : "Delete"
    static let groupNamePlaceholder = isChinese ? "分组名称" : "Group name"
    static let groupDefaultName = isChinese ? "分组" : "Group"
    static let groupNoGroups = isChinese ? "还没有分组，选择屏幕后点「录制此屏幕为新分组」" : "No groups yet — pick a screen and click \"Record screen as new group\""
    static let groupRecordEmpty = isChinese ? "该屏幕上没有可录制的窗口" : "No recordable windows on that screen"
    static func groupRecordedApps(_ count: Int) -> String {
        isChinese ? "已录制 \(count) 个应用" : "Recorded \(count) app\(count == 1 ? "" : "s")"
    }
    static func groupScreenName(_ index: Int, _ name: String) -> String {
        isChinese ? "屏幕 \(index + 1)：\(name)" : "Screen \(index + 1): \(name)"
    }

    // MARK: - Settings: Tabs

    static let preferencesTab = isChinese ? "偏好设置" : "Preferences"
    static let hotkeysTab = isChinese ? "快捷键" : "Hotkeys"
    static let aboutTab = isChinese ? "关于" : "About"

    // MARK: - Settings: Permissions

    static let permissionsTitle = isChinese ? "权限" : "Permissions"
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
    static let permissionGranted = isChinese ? "已授权" : "Granted"
    static let permissionGuide = isChinese ? "去开启" : "Grant Access"

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

    // MARK: - Settings: Switcher List Grouping

    static let switcherListTitle = isChinese ? "切换列表" : "Switcher List"
    static let groupingModeTitle = isChinese ? "分组方式" : "Grouping"
    static let groupingModeFlat = isChinese ? "按窗口（平铺）" : "By window (flat)"
    static let groupingModeByApp = isChinese ? "按应用" : "By app"
    static let groupingModeDescription = isChinese
        ? "「按窗口」每个窗口一行；「按应用」每个应用一行，选中后按 → 展开该应用的窗口。"
        : "\"By window\" lists every window; \"By app\" shows one row per app — press → to expand that app's windows."

    // MARK: - Settings: Hotkeys

    static let keyboardShortcutsTitle = isChinese ? "键盘快捷键" : "Keyboard Shortcuts"
    static let showSwitcherLabel = isChinese ? "切换快捷键" : "Switcher Hotkey"
    static let optionTabFootnote = isChinese
        ? "按住 Option 轻点 Tab 循环选择，松开 Option 完成切换。"
        : "Hold Option and tap Tab to cycle; release Option to switch."
    static let commandTabFootnote = isChinese
        ? "接管系统 ⌘+Tab：应用运行期间将替代系统自带的应用切换器，退出应用后自动恢复。"
        : "Takes over the system ⌘+Tab app switcher while this app is running; the native switcher is restored when the app quits."
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
