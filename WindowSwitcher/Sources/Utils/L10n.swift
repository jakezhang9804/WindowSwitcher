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
    static let noWindowsHint = isChinese ? "打开一个应用窗口后再试" : "Open an app window and try again"
    static let untitledWindow = isChinese ? "未命名窗口" : "Untitled Window"
    static let screenRecordingRequiredTitle = isChinese ? "需要屏幕录制权限" : "Screen Recording access required"
    static let screenRecordingRequiredDescription = isChinese
        ? "此权限仅用于读取窗口标题和布局，不会录制视频。"
        : "This access is used only to read window titles and layouts; WindowSwitcher does not record video."
    static let openSettings = isChinese ? "打开设置" : "Open Settings"
    static let drillHint = isChinese ? "查看窗口" : "Windows"
    static let launchApplication = isChinese ? "启动应用" : "Launch application"
    static let openBackgroundUtility = isChinese ? "打开后台工具" : "Open background utility"
    static let loadingApplications = isChinese ? "正在载入应用…" : "Loading applications..."
    static let loadingApplicationsHint = isChinese ? "首次搜索可能需要一点时间" : "The first search may take a moment"
    static let launchFailedTitle = isChinese ? "无法打开应用" : "Couldn’t open application"
    static func launchFailedMessage(_ name: String, _ reason: String) -> String {
        isChinese ? "无法打开“\(name)”：\(reason)" : "Couldn’t open \"\(name)\": \(reason)"
    }
    static let launchFailedUnknownReason = isChinese ? "应用不可用或系统拒绝了请求" : "The application is unavailable or macOS rejected the request"
    static let back = isChinese ? "返回" : "Back"
    static let clearSearch = isChinese ? "清除搜索" : "Clear search"
    static let searchWindowsAndApps = isChinese ? "搜索窗口和应用" : "Search windows and apps"
    static let activateItemHint = isChinese ? "按回车切换" : "Press Return to switch"
    static func quickSelectHint(_ index: Int) -> String {
        isChinese ? "按数字 \(index) 快速切换" : "Press \(index) to switch directly"
    }
    static func itemCountText(_ count: Int) -> String {
        isChinese ? "\(count) 项" : "\(count) item\(count == 1 ? "" : "s")"
    }

    // MARK: - App Groups

    static func groupMembers(_ count: Int) -> String {
        isChinese ? "\(count) 个应用" : "\(count) app\(count == 1 ? "" : "s")"
    }
    static let appGroupsTitle = isChinese ? "应用分组（屏幕录制）" : "App Groups (Screen Recording)"
    static let appGroupsDescription = isChinese
        ? "把某块屏幕上当前摆好的应用录制成一个分组。切换到分组时会启动其中的应用、恢复每个应用主窗口的位置和大小并全部前置。分组里的应用不会再单独出现在切换器中。"
        : "Record the apps arranged on a display as one group. Switching to it launches those apps, restores each app’s primary window position and size, and brings them forward. Group members no longer appear standalone in the switcher."
    static let groupRecordNew = isChinese ? "录制此屏幕为新分组" : "Record screen as new group"
    static let groupUpdateRecording = isChinese ? "更新录制" : "Re-record"
    static let deleteGroup = isChinese ? "删除" : "Delete"
    static let groupNamePlaceholder = isChinese ? "分组名称" : "Group name"
    static let groupDefaultName = isChinese ? "分组" : "Group"
    static let groupNoGroups = isChinese ? "还没有分组，选择屏幕后点「录制此屏幕为新分组」" : "No groups yet — pick a screen and click \"Record screen as new group\""
    static let groupRecordEmpty = isChinese ? "该屏幕上没有可录制的窗口" : "No recordable windows on that screen"
    static func groupConflict(_ groupNames: String) -> String {
        isChinese
            ? "部分应用已属于窗口组：\(groupNames)。请先从冲突分组中删除它们。"
            : "Some apps already belong to: \(groupNames). Remove the conflicting group before recording."
    }
    static let recordLayoutTitle = isChinese ? "录制窗口布局" : "Record a window layout"
    static let recordLayoutDescription = isChinese
        ? "先把窗口摆放到目标屏幕，再录制为一个可快速恢复的工作区。"
        : "Arrange windows on a display, then record them as a workspace you can restore in one step."
    static let deleteGroupConfirmationTitle = isChinese ? "删除这个窗口分组？" : "Delete this window group?"
    static let deleteGroupConfirmationMessage = isChinese
        ? "此操作会删除已保存的应用与窗口位置，且无法撤销。"
        : "The saved apps and window positions will be removed. This cannot be undone."
    static let rerecordGroupConfirmationTitle = isChinese ? "覆盖已保存的窗口布局？" : "Replace the saved window layout?"
    static let rerecordGroupConfirmationMessage = isChinese
        ? "将使用该分组绑定显示器上的当前应用和主窗口位置替换现有录制。"
        : "The current apps and primary-window positions on this group’s display will replace the existing recording."
    static let cancel = isChinese ? "取消" : "Cancel"
    static let ok = isChinese ? "确定" : "OK"
    static let saveFailedTitle = isChinese ? "保存失败" : "Couldn’t save changes"
    static let displayUnavailable = isChinese ? "显示器已断开" : "Display unavailable"
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
    static let generalSubtitle = isChinese ? "权限、启动行为与切换列表。" : "Permissions, launch behavior, and switcher organization."
    static let permissionHealthTitle = isChinese ? "权限状态" : "Permission Health"
    static let launchBehaviorTitle = isChinese ? "启动与后台行为" : "Launch & Behavior"
    static let showMenuBarIcon = isChinese ? "显示菜单栏图标" : "Show menu bar icon"
    static let showMenuBarIconDescription = isChinese
        ? "从菜单栏快速打开切换器和设置。"
        : "Keep quick access to the switcher and settings in the menu bar."
    static let startAtLogin = isChinese ? "开机启动" : "Start at login"
    static let startAtLoginDescription = isChinese
        ? "登录 Mac 后自动启动 WindowSwitcher。"
        : "Launch WindowSwitcher automatically when you sign in."
    static let startAtLoginFailed = isChinese ? "无法更新开机启动" : "Couldn’t update login item"

    // MARK: - Settings: Appearance

    static let appearanceTitle = isChinese ? "外观" : "Appearance"
    static let appearanceSubtitle = isChinese ? "选择切换器的外观和屏幕位置。" : "Choose how the switcher looks and where it appears."
    static let themeTitle = isChinese ? "主题" : "Theme"
    static let themeSystem = isChinese ? "跟随系统" : "System"
    static let themeLight = isChinese ? "浅色" : "Light"
    static let themeDark = isChinese ? "深色" : "Dark"
    static let panelPositionTitle = isChinese ? "面板位置" : "Panel Position"
    static let positionLeft = isChinese ? "左" : "Left"
    static let positionCenter = isChinese ? "中" : "Center"
    static let positionRight = isChinese ? "右" : "Right"
    static let panelPositionDescription = isChinese
        ? "居中使用紧凑横向 HUD；左右位置使用可搜索的纵向列表。"
        : "Center uses a compact horizontal HUD; left and right use a searchable vertical list."
    static let appearancePreviewTitle = isChinese ? "设置会立即生效" : "Changes apply instantly"
    static let appearancePreviewDescription = isChinese
        ? "下次打开切换器时即可看到新的主题和位置。"
        : "Open the switcher again to preview the selected theme and position."

    // MARK: - Settings: Show on Screen

    static let showOnScreenTitle = isChinese ? "显示屏幕" : "Show on screen"
    static let displaysTitle = isChinese ? "显示器" : "Displays"
    static let displaysSubtitle = isChinese ? "控制切换器在多显示器环境中的位置。" : "Control where the switcher appears in a multi-display setup."
    static let screenModeFocused = isChinese ? "鼠标所在屏幕" : "Pointer screen"
    static let screenModeFixed = isChinese ? "固定屏幕" : "Fixed screen"
    static let focusedScreenDescription = isChinese
        ? "切换器会出现在鼠标指针当前所在的屏幕。"
        : "The switcher follows the display that currently contains the pointer."
    static let fixedScreenDescription = isChinese
        ? "选择切换面板始终显示在哪个屏幕上。"
        : "Choose which screen the switcher panel always appears on."
    static let availableDisplaysTitle = isChinese ? "可用显示器" : "Available Displays"
    static let displayChangeHint = isChinese
        ? "连接、断开或重新排列显示器后，此列表会自动刷新。"
        : "This list refreshes automatically when displays are connected, disconnected, or rearranged."
    static let selectAvailableDisplay = isChinese
        ? "此前选择的显示器当前不可用，请从上方选择一台已连接的显示器。"
        : "The previously selected display is unavailable. Choose a connected display above."
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
    static let shortcutsSubtitle = isChinese ? "选择触发方式并查看完整键盘操作。" : "Choose the trigger and review every keyboard action."
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
        ? "在「窗口分组」中可以录制并快速恢复多应用窗口布局。"
        : "Use Window Groups to record and quickly restore multi-app window layouts."
    static let tipsTitle = isChinese ? "提示" : "Tips"
    static let keyboardNavigationTitle = isChinese ? "键盘导航" : "Keyboard Navigation"
    static let nextItemAction = isChinese ? "选择下一个项目" : "Select next item"
    static let previousItemAction = isChinese ? "选择上一个项目" : "Select previous item"
    static let openWindowsAction = isChinese ? "展开应用窗口" : "Open application windows"
    static let searchAction = isChinese ? "开始搜索 / 确认" : "Start search / confirm"
    static let quickSelectAction = isChinese ? "快速选择前九项" : "Quick-select the first nine items"
    static let dismissAction = isChinese ? "返回 / 关闭" : "Go back / dismiss"
    static let accessibilityRequiredTitle = isChinese ? "快捷键需要辅助功能权限" : "Accessibility permission is required"
    static let accessibilityRequiredDescription = isChinese
        ? "WindowSwitcher 只有在获得辅助功能权限后才能监听全局快捷键并激活其他应用窗口。"
        : "WindowSwitcher can monitor the global trigger and activate other apps only after Accessibility access is granted."

    // MARK: - Settings: About

    static let aboutDescription = isChinese
        ? "一个快速、原生的 macOS 窗口切换器"
        : "A fast and native window switcher for macOS"
    static let aboutSubtitle = isChinese ? "版本、更新与项目链接。" : "Version, updates, and project links."
    static func versionLabel(_ version: String) -> String {
        isChinese ? "版本 \(version)" : "Version \(version)"
    }
    static let softwareUpdateTitle = isChinese ? "软件更新" : "Software Update"
    static let linksTitle = isChinese ? "链接" : "Links"
    static let sourceCodeTitle = isChinese ? "源代码与问题反馈" : "Source Code & Issues"
    static let checkForUpdates = isChinese ? "检查更新" : "Check for Updates"
    static let checkingForUpdates = isChinese ? "正在检查更新…" : "Checking for updates..."
    static func updateAvailable(_ version: String) -> String {
        isChinese ? "版本 \(version) 可用！" : "Version \(version) is available!"
    }
    static let downloadUpdate = isChinese ? "下载更新" : "Download Update"
    static let viewReleaseNotes = isChinese ? "查看发布说明" : "View Release Notes"
    static let skipVersion = isChinese ? "跳过此版本" : "Skip This Version"
    static let updateSkippedTitle = isChinese ? "已跳过此版本" : "Update skipped"
    static func updateSkippedDescription(_ version: String) -> String {
        isChinese ? "版本 \(version) 不会再次提示；后续新版本仍会正常显示。" : "Version \(version) won’t be offered again; newer releases will still appear."
    }
    static let readyToCheckUpdates = isChinese ? "准备检查更新" : "Ready to check for updates"
    static let readyToCheckUpdatesDescription = isChinese
        ? "当前安装版本显示在上方。"
        : "Your installed version is shown above."
    static let upToDateTitle = isChinese ? "已是最新版本" : "WindowSwitcher is up to date"
    static let upToDateDescription = isChinese ? "你正在使用当前版本。" : "You’re running the current version."
    static let updateCheckFailedTitle = isChinese ? "无法检查更新" : "Couldn’t check for updates"
    static let invalidUpdateURL = isChinese ? "更新服务地址无效" : "The update service URL is invalid"
    static let invalidServerResponse = isChinese ? "更新服务器返回了无效响应" : "The update server returned an invalid response"
    static let noReleasesFound = isChinese ? "暂未找到可用版本" : "No releases are available"
    static func updateHTTPError(_ code: Int) -> String {
        isChinese ? "更新服务器错误（HTTP \(code)）" : "Update server error (HTTP \(code))"
    }
    static let couldNotOpenUpdateLink = isChinese ? "无法用浏览器打开更新链接" : "The update link couldn’t be opened"
    static let invalidUpdateLink = isChinese ? "更新链接无效或不受信任" : "The update link is invalid or untrusted"
    static let unknownApp = isChinese ? "未知应用" : "Unknown App"

    // MARK: - Settings: Window Groups

    static let windowGroupsTitle = isChinese ? "窗口分组" : "Window Groups"
    static let windowGroupsSubtitle = isChinese ? "录制并一键恢复多应用窗口布局。" : "Record and restore multi-app window layouts in one step."
    static let windowGroupsHowItWorksTitle = isChinese ? "工作原理" : "How it works"

    // MARK: - Menu Bar

    static let showSwitcher = isChinese ? "显示切换器" : "Show Switcher"
    static let preferences = isChinese ? "偏好设置" : "Preferences"
    static let quit = isChinese ? "退出" : "Quit"
    static let quitDescription = isChinese ? "停止全局快捷键并退出应用。" : "Stop the global hotkey and quit the app."
}
