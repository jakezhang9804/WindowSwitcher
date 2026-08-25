import SwiftUI
import AppKit
import AppSwitcherKit
import PermissionFlow

// MARK: - Settings Navigation

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case displays
    case windowGroups
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.generalTitle
        case .appearance: return L10n.appearanceTitle
        case .displays: return L10n.displaysTitle
        case .windowGroups: return L10n.windowGroupsTitle
        case .shortcuts: return L10n.keyboardShortcutsTitle
        case .about: return L10n.aboutTab
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "circle.lefthalf.filled"
        case .displays: return "display.2"
        case .windowGroups: return "rectangle.3.group"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

/// A compact, native settings center. The previous long Form hid advanced
/// controls below the fold; a sidebar keeps every page discoverable and stable.
struct SettingsView: View {
    @State private var selection: SettingsSection? = .general
    @AppStorage("appTheme") private var appTheme = "system"

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 176, ideal: 188, max: 210)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WindowSwitcher")
                            .font(.caption.weight(.semibold))
                        Text("v\(appVersion)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettingsPage()
                case .appearance: AppearanceSettingsPage()
                case .displays: DisplaysSettingsPage()
                case .windowGroups: WindowGroupsSettingsPage()
                case .shortcuts: ShortcutsSettingsPage()
                case .about: AboutSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 800, minHeight: 540, idealHeight: 620)
        .preferredColorScheme(preferredColorScheme)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7.0"
    }

    private var preferredColorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

// MARK: - Shared Settings Components

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                content()
            }
            .frame(maxWidth: 680, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String?
    let symbol: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, symbol: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 7) {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(.tint)
                    }
                    Text(title)
                        .font(.headline)
                }
                .padding(.bottom, 12)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
        )
    }
}

private struct SettingsRow<Accessory: View>: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)
            accessory()
        }
        .frame(minHeight: 38)
    }
}

private struct StatusCallout: View {
    enum Kind { case info, success, warning, error }

    let kind: Kind
    let title: String
    let message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.18), lineWidth: 0.5))
    }

    private var color: Color {
        switch kind {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

private struct DividerRow: View {
    var body: some View {
        Divider().padding(.leading, 42).padding(.vertical, 11)
    }
}

// MARK: - General

private struct GeneralSettingsPage: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("tabListGroupingMode") private var groupingMode = "byApp"
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some View {
        SettingsPage(
            title: L10n.generalTitle,
            subtitle: L10n.generalSubtitle
        ) {
            SettingsCard(title: L10n.permissionHealthTitle, symbol: "checkmark.shield") {
                permissionRow(
                    icon: "accessibility",
                    color: .blue,
                    title: L10n.accessibilityTitle,
                    description: L10n.accessibilityDescription,
                    pane: .accessibility
                )
                DividerRow()
                permissionRow(
                    icon: "record.circle",
                    color: .purple,
                    title: L10n.screenRecordingTitle,
                    description: L10n.screenRecordingDescription,
                    pane: .screenRecording
                )

                Text(L10n.permissionsRestart)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }

            SettingsCard(title: L10n.launchBehaviorTitle, symbol: "power") {
                SettingsRow(
                    icon: "menubar.rectangle",
                    color: .indigo,
                    title: L10n.showMenuBarIcon,
                    description: L10n.showMenuBarIconDescription
                ) {
                    Toggle("", isOn: $showMenuBarIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                DividerRow()

                SettingsRow(
                    icon: "arrow.clockwise.circle",
                    color: .green,
                    title: L10n.startAtLogin,
                    description: L10n.startAtLoginDescription
                ) {
                    Toggle("", isOn: $settingsVM.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if let error = settingsVM.launchAtLoginError {
                    StatusCallout(kind: .error, title: L10n.startAtLoginFailed, message: error)
                        .padding(.top, 12)
                }
            }

            SettingsCard(title: L10n.switcherListTitle, symbol: "rectangle.3.group") {
                Picker(L10n.groupingModeTitle, selection: $groupingMode) {
                    Text(L10n.groupingModeByApp).tag("byApp")
                    Text(L10n.groupingModeFlat).tag("flat")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(L10n.groupingModeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    private func permissionRow(
        icon: String,
        color: Color,
        title: String,
        description: String,
        pane: PermissionFlowPane
    ) -> some View {
        SettingsRow(icon: icon, color: color, title: title, description: description) {
            PermissionFlowButton(pane: pane, suggestedAppURLs: [Bundle.main.bundleURL]) { state in
                if state.isGranted {
                    Label(L10n.permissionGranted, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Label(L10n.permissionGuide, systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPage: View {
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("panelPosition") private var panelPosition = "center"

    var body: some View {
        SettingsPage(title: L10n.appearanceTitle, subtitle: L10n.appearanceSubtitle) {
            SettingsCard(title: L10n.themeTitle, symbol: "circle.lefthalf.filled") {
                HStack(spacing: 10) {
                    ThemeChoice(title: L10n.themeSystem, value: "system", selection: $appTheme, style: .system)
                    ThemeChoice(title: L10n.themeLight, value: "light", selection: $appTheme, style: .light)
                    ThemeChoice(title: L10n.themeDark, value: "dark", selection: $appTheme, style: .dark)
                }
            }

            SettingsCard(title: L10n.panelPositionTitle, symbol: "rectangle.inset.filled") {
                Picker(L10n.panelPositionTitle, selection: $panelPosition) {
                    Label(L10n.positionLeft, systemImage: "rectangle.leftthird.inset.filled").tag("left")
                    Label(L10n.positionCenter, systemImage: "rectangle.center.inset.filled").tag("center")
                    Label(L10n.positionRight, systemImage: "rectangle.rightthird.inset.filled").tag("right")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(L10n.panelPositionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            StatusCallout(
                kind: .info,
                title: L10n.appearancePreviewTitle,
                message: L10n.appearancePreviewDescription
            )
        }
    }
}

private struct ThemeChoice: View {
    enum PreviewStyle { case system, light, dark }

    let title: String
    let value: String
    @Binding var selection: String
    let style: PreviewStyle

    var body: some View {
        Button {
            selection = value
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(background)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(surface)
                        .frame(width: 64, height: 30)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 18)
                                .padding(.leading, 6)
                        }
                }
                .frame(height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selection == value ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selection == value ? 2 : 0.5)
                )

                HStack(spacing: 5) {
                    Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection == value ? Color.accentColor : .secondary)
                    Text(title).font(.caption.weight(.medium))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }

    private var background: Color {
        switch style {
        case .system: return Color(nsColor: .windowBackgroundColor)
        case .light: return Color(white: 0.94)
        case .dark: return Color(white: 0.12)
        }
    }

    private var surface: Color {
        switch style {
        case .system: return Color.primary.opacity(0.12)
        case .light: return Color.white
        case .dark: return Color(white: 0.22)
        }
    }
}

// MARK: - Displays

private struct DisplaysSettingsPage: View {
    @AppStorage("screenMode") private var screenMode = "focused"
    @AppStorage("selectedScreenIndex") private var selectedScreenIndex = 0
    @AppStorage("selectedScreenID") private var selectedScreenID = ""
    @State private var screens: [NSScreen] = NSScreen.screens

    var body: some View {
        SettingsPage(title: L10n.displaysTitle, subtitle: L10n.displaysSubtitle) {
            SettingsCard(title: L10n.showOnScreenTitle, symbol: "display.2") {
                Picker(L10n.showOnScreenTitle, selection: $screenMode) {
                    Text(L10n.screenModeFocused).tag("focused")
                    Text(L10n.screenModeFixed).tag("fixed")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(screenMode == "focused" ? L10n.focusedScreenDescription : L10n.fixedScreenDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            if screenMode == "fixed" {
                SettingsCard(title: L10n.availableDisplaysTitle, symbol: "rectangle.connected.to.line.below") {
                    ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                        Button {
                            selectedScreenIndex = index
                            selectedScreenID = screen.persistentDisplayID ?? ""
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "display")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.tint)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(screen.localizedName)
                                        .font(.body.weight(.medium))
                                    Text(L10n.groupScreenName(index, screen.localizedName))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: isSelected(screen, at: index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected(screen, at: index) ? Color.accentColor : .secondary)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected(screen, at: index) ? .isSelected : [])

                        if index < screens.count - 1 { Divider() }
                    }
                }

                if selectedDisplayUnavailable {
                    StatusCallout(
                        kind: .warning,
                        title: L10n.displayUnavailable,
                        message: L10n.selectAvailableDisplay
                    )
                }
            }

            StatusCallout(
                kind: .info,
                title: L10n.screensDetected(screens.count),
                message: L10n.displayChangeHint
            )
        }
        .onAppear { migrateLegacyScreenSelectionIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }

    private func isSelected(_ screen: NSScreen, at index: Int) -> Bool {
        if !selectedScreenID.isEmpty {
            return screen.persistentDisplayID == selectedScreenID
        }
        return selectedScreenIndex == index
    }

    private var selectedDisplayUnavailable: Bool {
        !selectedScreenID.isEmpty && !screens.contains { $0.persistentDisplayID == selectedScreenID }
    }

    private func migrateLegacyScreenSelectionIfNeeded() {
        guard selectedScreenID.isEmpty, screens.indices.contains(selectedScreenIndex) else { return }
        selectedScreenID = screens[selectedScreenIndex].persistentDisplayID ?? ""
    }
}

// MARK: - Window Groups

private struct WindowGroupsSettingsPage: View {
    var body: some View {
        SettingsPage(title: L10n.windowGroupsTitle, subtitle: L10n.windowGroupsSubtitle) {
            StatusCallout(kind: .info, title: L10n.windowGroupsHowItWorksTitle, message: L10n.appGroupsDescription)

            SettingsCard {
                AppGroupsSection()
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsPage: View {
    @AppStorage("useCommandTab") private var useCommandTab = false

    var body: some View {
        SettingsPage(title: L10n.keyboardShortcutsTitle, subtitle: L10n.shortcutsSubtitle) {
            SettingsCard(title: L10n.showSwitcherLabel, symbol: "keyboard") {
                HotkeyChoice(
                    title: "⌥  Option + Tab",
                    description: L10n.optionTabFootnote,
                    isSelected: !useCommandTab
                ) { useCommandTab = false }

                Divider().padding(.vertical, 10)

                HotkeyChoice(
                    title: "⌘  Command + Tab",
                    description: L10n.commandTabFootnote,
                    isSelected: useCommandTab
                ) { useCommandTab = true }
            }

            SettingsCard(title: L10n.keyboardNavigationTitle, symbol: "arrowkeys") {
                ShortcutReferenceRow(keys: ["Tab", "↓"], action: L10n.nextItemAction)
                Divider().padding(.vertical, 8)
                ShortcutReferenceRow(keys: ["⇧", "Tab", "↑"], action: L10n.previousItemAction)
                Divider().padding(.vertical, 8)
                ShortcutReferenceRow(keys: ["→"], action: L10n.openWindowsAction)
                Divider().padding(.vertical, 8)
                ShortcutReferenceRow(keys: ["↩"], action: L10n.searchAction)
                Divider().padding(.vertical, 8)
                ShortcutReferenceRow(keys: ["1", "…", "9"], action: L10n.quickSelectAction)
                Divider().padding(.vertical, 8)
                ShortcutReferenceRow(keys: ["esc"], action: L10n.dismissAction)
            }

            StatusCallout(kind: .warning, title: L10n.accessibilityRequiredTitle, message: L10n.accessibilityRequiredDescription)
        }
    }
}

private struct HotkeyChoice: View {
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ShortcutReferenceRow: View {
    let keys: [String]
    let action: String

    var body: some View {
        HStack {
            Text(action).font(.callout)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                        .frame(minHeight: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                }
            }
        }
    }
}

// MARK: - About & Updates

private struct AboutSettingsPage: View {
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        SettingsPage(title: L10n.aboutTab, subtitle: L10n.aboutSubtitle) {
            SettingsCard {
                HStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 78, height: 78)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("WindowSwitcher")
                            .font(.title2.bold())
                        Text(L10n.versionLabel(currentVersion))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(L10n.aboutDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            SettingsCard(title: L10n.softwareUpdateTitle, symbol: "arrow.triangle.2.circlepath") {
                updateContent
            }

            SettingsCard(title: L10n.linksTitle, symbol: "link") {
                Link(destination: URL(string: "https://github.com/jakezhang9804/WindowSwitcher")!) {
                    SettingsRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        color: .indigo,
                        title: L10n.sourceCodeTitle,
                        description: "github.com/jakezhang9804/WindowSwitcher"
                    ) {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                DividerRow()

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    SettingsRow(
                        icon: "power",
                        color: .red,
                        title: L10n.quit,
                        description: L10n.quitDescription
                    ) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Text(L10n.isChinese ? "基于" : "Powered by")
                    .foregroundStyle(.secondary)
                Link("Manus", destination: URL(string: "https://manus.im")!)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        if updateService.isChecking {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L10n.checkingForUpdates)
                Spacer()
            }
        } else if updateService.isUpdateAvailable, let version = updateService.latestVersion {
            VStack(alignment: .leading, spacing: 12) {
                StatusCallout(kind: .success, title: L10n.updateAvailable(version), message: updateService.releaseNotes)
                HStack {
                    Button(L10n.downloadUpdate) { updateService.openDownload() }
                        .buttonStyle(.borderedProminent)
                    Button(L10n.viewReleaseNotes) { updateService.openReleasePage() }
                        .buttonStyle(.bordered)
                    Button(L10n.skipVersion) { updateService.skipCurrentUpdate() }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: updateStatusSymbol)
                    .foregroundStyle(updateStatusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(updateStatusTitle)
                        .font(.callout.weight(.medium))
                    Text(updateStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.checkForUpdates) {
                    Task { await updateService.checkForUpdates() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var updateStatusSymbol: String {
        if updateService.lastError != nil { return "exclamationmark.triangle.fill" }
        if updateService.hasSkippedLatestVersion { return "forward.end.circle.fill" }
        return updateService.hasCompletedCheck ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
    }

    private var updateStatusColor: Color {
        if updateService.lastError != nil { return .orange }
        if updateService.hasSkippedLatestVersion { return .secondary }
        return updateService.hasCompletedCheck ? .green : .secondary
    }

    private var updateStatusTitle: String {
        if updateService.lastError != nil { return L10n.updateCheckFailedTitle }
        if updateService.hasSkippedLatestVersion { return L10n.updateSkippedTitle }
        return updateService.hasCompletedCheck ? L10n.upToDateTitle : L10n.readyToCheckUpdates
    }

    private var updateStatusDescription: String {
        if updateService.hasSkippedLatestVersion {
            return L10n.updateSkippedDescription(updateService.latestVersion ?? "")
        }
        return updateService.lastError
            ?? (updateService.hasCompletedCheck ? L10n.upToDateDescription : L10n.readyToCheckUpdatesDescription)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7.0"
    }
}

// MARK: - App Groups

struct AppGroupsSection: View {
    @StateObject private var groupsVM = AppGroupsViewModel()

    private let windowService = WindowService()

    @State private var recordScreenIndex = 0
    @State private var lastActionMessage: String?
    @State private var lastActionWasError = false
    @State private var isRecording = false
    @State private var pendingDelete: AppGroup?
    @State private var pendingRerecord: AppGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.recordLayoutTitle)
                    .font(.headline)
                Text(L10n.recordLayoutDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Picker(L10n.showOnScreenTitle, selection: $recordScreenIndex) {
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                            Text(L10n.groupScreenName(index, screen.localizedName)).tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)

                    Button {
                        Task { @MainActor in
                            isRecording = true
                            await Task.yield()
                            recordNewGroup()
                            isRecording = false
                        }
                    } label: {
                        if isRecording {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(L10n.groupRecordNew, systemImage: "record.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecording || NSScreen.screens.isEmpty)
                }
            }

            if let message = groupsVM.saveError {
                StatusCallout(kind: .error, title: L10n.saveFailedTitle, message: message)
            } else if let message = lastActionMessage {
                StatusCallout(
                    kind: lastActionWasError ? .warning : .success,
                    title: message,
                    message: nil
                )
            }

            Divider()

            if groupsVM.groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L10n.groupNoGroups)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                VStack(spacing: 10) {
                    ForEach(groupsVM.groups) { group in
                        groupRow(group)
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.deleteGroupConfirmationTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.deleteGroup, role: .destructive) {
                if let pendingDelete { groupsVM.delete(pendingDelete) }
                pendingDelete = nil
            }
            Button(L10n.cancel, role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L10n.deleteGroupConfirmationMessage)
        }
        .confirmationDialog(
            L10n.rerecordGroupConfirmationTitle,
            isPresented: Binding(
                get: { pendingRerecord != nil },
                set: { if !$0 { pendingRerecord = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.groupUpdateRecording) {
                if let pendingRerecord { updateRecording(pendingRerecord) }
                pendingRerecord = nil
            }
            Button(L10n.cancel, role: .cancel) { pendingRerecord = nil }
        } message: {
            Text(L10n.rerecordGroupConfirmationMessage)
        }
    }

    private func groupRow(_ group: AppGroup) -> some View {
        HStack(spacing: 12) {
            GroupStackIcon(icons: icons(for: group), size: 40)

            VStack(alignment: .leading, spacing: 3) {
                GroupNameField(name: group.name) { groupsVM.rename(group, to: $0) }
                Text("\(L10n.groupMembers(group.bundleIDs.count)) · \(screenLabel(group))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                pendingRerecord = group
            } label: {
                Label(L10n.groupUpdateRecording, systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                pendingDelete = group
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.deleteGroup)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func recordNewGroup() {
        let screens = NSScreen.screens
        guard screens.indices.contains(recordScreenIndex) else {
            lastActionMessage = L10n.displayUnavailable
            lastActionWasError = true
            return
        }

        let recording = windowService.recordScreen(screenIndex: recordScreenIndex)
        guard !recording.bundleIDs.isEmpty else {
            lastActionMessage = L10n.groupRecordEmpty
            lastActionWasError = true
            return
        }

        let conflictingGroups = groupsVM.conflictingGroupNames(for: recording.bundleIDs)
        guard conflictingGroups.isEmpty else {
            lastActionMessage = L10n.groupConflict(conflictingGroups.joined(separator: ", "))
            lastActionWasError = true
            return
        }

        let saved = groupsVM.upsert(AppGroup(
            name: defaultGroupName(),
            bundleIDs: recording.bundleIDs,
            screenIndex: recordScreenIndex,
            displayID: screens[recordScreenIndex].persistentDisplayID,
            frames: recording.frames
        ))
        if saved {
            lastActionMessage = L10n.groupRecordedApps(recording.bundleIDs.count)
            lastActionWasError = false
        }
    }

    private func updateRecording(_ group: AppGroup) {
        guard let screenIndex = screenIndex(for: group) else {
            lastActionMessage = L10n.displayUnavailable
            lastActionWasError = true
            return
        }

        let recording = windowService.recordScreen(screenIndex: screenIndex)
        guard !recording.bundleIDs.isEmpty else {
            lastActionMessage = L10n.groupRecordEmpty
            lastActionWasError = true
            return
        }

        let conflictingGroups = groupsVM.conflictingGroupNames(for: recording.bundleIDs, excluding: group.id)
        guard conflictingGroups.isEmpty else {
            lastActionMessage = L10n.groupConflict(conflictingGroups.joined(separator: ", "))
            lastActionWasError = true
            return
        }

        var updated = group
        updated.bundleIDs = recording.bundleIDs
        updated.screenIndex = screenIndex
        updated.displayID = NSScreen.screens[screenIndex].persistentDisplayID
        updated.frames = recording.frames
        if groupsVM.upsert(updated) {
            lastActionMessage = L10n.groupRecordedApps(recording.bundleIDs.count)
            lastActionWasError = false
        }
    }

    private func defaultGroupName() -> String {
        let base = L10n.groupDefaultName
        let existing = Set(groupsVM.groups.map(\.name))
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func icons(for group: AppGroup) -> [NSImage] {
        group.bundleIDs.compactMap { bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    private func screenLabel(_ group: AppGroup) -> String {
        let screens = NSScreen.screens
        guard let index = screenIndex(for: group) else { return L10n.displayUnavailable }
        return L10n.groupScreenName(index, screens[index].localizedName)
    }

    private func screenIndex(for group: AppGroup) -> Int? {
        let screens = NSScreen.screens
        if let screen = NSScreen.screen(withPersistentDisplayID: group.displayID),
           let index = screens.firstIndex(of: screen) {
            return index
        }
        guard group.displayID == nil, screens.indices.contains(group.screenIndex) else { return nil }
        return group.screenIndex
    }
}

struct GroupNameField: View {
    let name: String
    let onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(name: String, onCommit: @escaping (String) -> Void) {
        self.name = name
        self.onCommit = onCommit
        _text = State(initialValue: name)
    }

    var body: some View {
        TextField(L10n.groupNamePlaceholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: name) { _, newName in if !focused { text = newName } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { text = name } else { onCommit(trimmed) }
    }
}

@MainActor
final class AppGroupsViewModel: ObservableObject {
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var saveError: String?

    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private var currentSettings = SwitcherSettings()

    init() { reload() }

    func reload() {
        currentSettings = settingsStore.load()
        groups = currentSettings.appGroups
    }

    func conflictingGroupNames(for bundleIDs: [String], excluding excludedID: UUID? = nil) -> [String] {
        let candidates = Set(bundleIDs.map { $0.lowercased() })
        return groups.compactMap { group in
            guard group.id != excludedID else { return nil }
            let members = Set(group.bundleIDs.map { $0.lowercased() })
            return candidates.isDisjoint(with: members) ? nil : group.name
        }
    }

    @discardableResult
    func upsert(_ group: AppGroup) -> Bool {
        if let index = currentSettings.appGroups.firstIndex(where: { $0.id == group.id }) {
            currentSettings.appGroups[index] = group
        } else {
            currentSettings.appGroups.append(group)
        }
        return save()
    }

    func rename(_ group: AppGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = currentSettings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
        currentSettings.appGroups[index].name = trimmed
        _ = save()
    }

    func delete(_ group: AppGroup) {
        currentSettings.appGroups.removeAll { $0.id == group.id }
        _ = save()
    }

    @discardableResult
    private func save() -> Bool {
        var persisted = settingsStore.load()
        persisted.appGroups = currentSettings.appGroups
        do {
            try settingsStore.save(persisted)
            saveError = nil
            reload()
            NotificationCenter.default.post(name: .switcherSettingsDidChange, object: nil)
            return true
        } catch {
            saveError = error.localizedDescription
            reload()
            return false
        }
    }
}

extension Notification.Name {
    static let switcherSettingsDidChange = Notification.Name("switcherSettingsDidChange")
}
