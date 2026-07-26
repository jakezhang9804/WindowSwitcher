import SwiftUI
import KeyboardShortcuts
import AppSwitcherKit
import PermissionFlow

/// Settings window
/// 3 Tabs: Preferences, Hotkeys, About
struct SettingsView: View {
    var body: some View {
        TabView {
            PreferencesTab()
                .tabItem {
                    Label(L10n.preferencesTab, systemImage: "gearshape")
                }

            HotkeysTab()
                .tabItem {
                    Label(L10n.hotkeysTab, systemImage: "command")
                }

            AboutTab()
                .tabItem {
                    Label(L10n.aboutTab, systemImage: "info.circle")
                }
        }
        .frame(width: 620, height: 700)
    }
}

// MARK: - Preferences Tab

struct PreferencesTab: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("panelPosition") private var panelPosition = "center"
    @AppStorage("screenMode") private var screenMode = "focused"
    @AppStorage("selectedScreenIndex") private var selectedScreenIndex = 0
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("tabListGroupingMode") private var tabListGroupingMode = "byApp"

    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var appConfigVM = AppConfigViewModel()

    var body: some View {
        Form {
            // Permissions — live status plus PermissionFlow's guided grant flow
            // (opens the right privacy pane and floats a drag-in helper panel)
            Section {
                permissionRow(
                    icon: "accessibility",
                    iconColor: .blue,
                    title: L10n.accessibilityTitle,
                    description: L10n.accessibilityDescription,
                    pane: .accessibility
                )
                permissionRow(
                    icon: "record.circle",
                    iconColor: .purple,
                    title: L10n.screenRecordingTitle,
                    description: L10n.screenRecordingDescription,
                    pane: .screenRecording
                )
            } header: {
                Text(L10n.permissionsTitle)
            } footer: {
                Text(L10n.permissionsRestart)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // General — switches on the right, matching System Settings
            Section(L10n.generalTitle) {
                Toggle(L10n.showMenuBarIcon, isOn: $showMenuBarIcon)
                Toggle(L10n.startAtLogin, isOn: $settingsVM.launchAtLogin)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            // Appearance
            Section(L10n.appearanceTitle) {
                Picker(L10n.themeTitle, selection: $appTheme) {
                    Text(L10n.themeSystem).tag("system")
                    Text(L10n.themeLight).tag("light")
                    Text(L10n.themeDark).tag("dark")
                }
                Picker(L10n.panelPositionTitle, selection: $panelPosition) {
                    Text(L10n.positionLeft).tag("left")
                    Text(L10n.positionCenter).tag("center")
                    Text(L10n.positionRight).tag("right")
                }
            }

            // Show on Screen
            Section {
                Picker(L10n.showOnScreenTitle, selection: $screenMode) {
                    Text(L10n.screenModeFocused).tag("focused")
                    Text(L10n.screenModeFixed).tag("fixed")
                }

                if screenMode == "fixed" {
                    Picker(L10n.screenModeFixed, selection: $selectedScreenIndex) {
                        ForEach(Array(screenNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                }
            } footer: {
                if screenMode == "fixed" {
                    Text("\(L10n.fixedScreenDescription) \(L10n.screensDetected(NSScreen.screens.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Switcher list grouping — flat window list vs. TabTab-style
            // per-app grouping (one row per app, secondary panel for windows)
            Section {
                Picker(L10n.groupingModeTitle, selection: $tabListGroupingMode) {
                    Text(L10n.groupingModeFlat).tag("flat")
                    Text(L10n.groupingModeByApp).tag("byApp")
                }
            } header: {
                Text(L10n.switcherListTitle)
            } footer: {
                Text(L10n.groupingModeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // App Groups — record a screen's window layout as one switcher entry
            Section {
                AppGroupsSection(appConfigVM: appConfigVM)
            } header: {
                Text(L10n.appGroupsTitle)
            } footer: {
                Text(L10n.appGroupsDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Permission Row

    private func permissionRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        pane: PermissionFlowPane
    ) -> some View {
        LabeledContent {
            PermissionFlowButton(
                pane: pane,
                suggestedAppURLs: [Bundle.main.bundleURL]
            ) { state in
                if state.isGranted {
                    Label(L10n.permissionGranted, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(L10n.permissionGuide, systemImage: "arrow.right.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(iconColor.gradient))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Screen Names

    private var screenNames: [String] {
        NSScreen.screens.enumerated().map { index, screen in
            screen.localizedName
        }
    }
}

// MARK: - Hotkeys Tab

struct HotkeysTab: View {
    @AppStorage("useCommandTab") private var useCommandTab = false

    var body: some View {
        Form {
            Section {
                Picker(L10n.showSwitcherLabel, selection: $useCommandTab) {
                    Text("⌥ Option + Tab").tag(false)
                    Text("⌘ Command + Tab").tag(true)
                }
            } header: {
                Text(L10n.keyboardShortcutsTitle)
            } footer: {
                Text(useCommandTab ? L10n.commandTabFootnote : L10n.optionTabFootnote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text(L10n.hotkeysTip1)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(L10n.hotkeysTip2)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.tipsTitle)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("WindowSwitcher")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(currentVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(L10n.aboutDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Update section
            updateSection

            Spacer()

            // Powered by Manus
            poweredByManus
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Update Section

    @ViewBuilder
    private var updateSection: some View {
        if updateService.isChecking {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.checkingForUpdates)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        } else if updateService.isUpdateAvailable, let version = updateService.latestVersion {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(L10n.updateAvailable(version))
                        .font(.callout)
                        .fontWeight(.medium)
                }

                if let notes = updateService.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 12) {
                    Button(L10n.downloadUpdate) {
                        updateService.openDownload()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.skipVersion) {
                        updateService.skipCurrentUpdate()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } else {
            Button(L10n.checkForUpdates) {
                Task {
                    await updateService.checkForUpdates()
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)

            if let error = updateService.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Powered by Manus

    private var poweredByManus: some View {
        HStack(spacing: 4) {
            Text(L10n.isChinese ? "基于" : "Powered by")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Link("Manus", destination: URL(string: "https://manus.im")!)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .padding(.bottom, 8)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - App Display Item

struct AppDisplayItem: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let icon: NSImage?

    init(from installedApp: InstalledApp) {
        self.id = installedApp.bundleID
        self.name = installedApp.displayName
        self.bundleID = installedApp.bundleID
        self.icon = NSWorkspace.shared.icon(forFile: installedApp.bundlePath)
    }

    init(from runningApp: NSRunningApplication) {
        self.id = runningApp.bundleIdentifier ?? "\(runningApp.processIdentifier)"
        self.name = runningApp.localizedName ?? "Unknown"
        self.bundleID = runningApp.bundleIdentifier ?? ""
        self.icon = runningApp.icon
    }
}

// MARK: - App Config ViewModel

/// Provides the installed/running app catalog — used by the App Groups section
/// to resolve member icons.
@MainActor
class AppConfigViewModel: ObservableObject {
    @Published var apps: [AppDisplayItem] = []

    private let catalog = InstalledAppCatalog()

    init() {
        loadApps()
    }

    private func loadApps() {
        let installedApps = catalog.fetchInstalledApps()
        var appsByBundleID: [String: AppDisplayItem] = [:]

        for app in installedApps {
            appsByBundleID[app.bundleID] = AppDisplayItem(from: app)
        }

        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        for app in runningApps {
            if let bundleID = app.bundleIdentifier, appsByBundleID[bundleID] == nil {
                appsByBundleID[bundleID] = AppDisplayItem(from: app)
            }
        }

        apps = Array(appsByBundleID.values)
    }
}

// MARK: - App Groups Section

/// A group is a *screen recording*: pick a screen, arrange your windows, record.
/// The apps on that screen (and their positions/sizes) become the group. There
/// is no manual app selection — members are whatever is on the screen.
struct AppGroupsSection: View {
    @ObservedObject var appConfigVM: AppConfigViewModel
    @StateObject private var groupsVM = AppGroupsViewModel()

    private let windowService = WindowService()

    @State private var recordScreenIndex = 0
    @State private var lastActionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Record a new group from a screen
            HStack(spacing: 8) {
                Picker("", selection: $recordScreenIndex) {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Text(L10n.groupScreenName(index, screen.localizedName)).tag(index)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)

                Button(L10n.groupRecordNew) { recordNewGroup() }
                    .buttonStyle(.borderedProminent)
            }

            if let msg = lastActionMessage {
                Text(msg).font(.caption).foregroundColor(.secondary)
            }

            if groupsVM.groups.isEmpty {
                Text(L10n.groupNoGroups)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(groupsVM.groups) { group in
                    groupRow(group)
                    if group.id != groupsVM.groups.last?.id { Divider() }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func groupRow(_ group: AppGroup) -> some View {
        HStack(spacing: 10) {
            GroupStackIcon(icons: icons(for: group), size: 30)

            VStack(alignment: .leading, spacing: 2) {
                GroupNameField(name: group.name) { groupsVM.rename(group, to: $0) }
                Text("\(L10n.groupMembers(group.bundleIDs.count)) · \(screenLabel(group.screenIndex))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(L10n.groupUpdateRecording) { updateRecording(group) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(L10n.deleteGroup, role: .destructive) { groupsVM.delete(group) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: Actions

    private func recordNewGroup() {
        let recording = windowService.recordScreen(screenIndex: recordScreenIndex)
        guard !recording.bundleIDs.isEmpty else {
            lastActionMessage = L10n.groupRecordEmpty
            return
        }
        groupsVM.upsert(AppGroup(
            name: defaultGroupName(),
            bundleIDs: recording.bundleIDs,
            screenIndex: recordScreenIndex,
            frames: recording.frames
        ))
        lastActionMessage = L10n.groupRecordedApps(recording.bundleIDs.count)
    }

    private func updateRecording(_ group: AppGroup) {
        let recording = windowService.recordScreen(screenIndex: group.screenIndex)
        guard !recording.bundleIDs.isEmpty else {
            lastActionMessage = L10n.groupRecordEmpty
            return
        }
        var updated = group
        updated.bundleIDs = recording.bundleIDs
        updated.frames = recording.frames
        groupsVM.upsert(updated)
        lastActionMessage = L10n.groupRecordedApps(recording.bundleIDs.count)
    }

    private func defaultGroupName() -> String {
        let base = L10n.groupDefaultName
        let existing = Set(groupsVM.groups.map { $0.name })
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func icons(for group: AppGroup) -> [NSImage] {
        let byBundleID = Dictionary(
            appConfigVM.apps.map { ($0.bundleID.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return group.bundleIDs.compactMap { byBundleID[$0.lowercased()]?.icon }
    }

    private func screenLabel(_ index: Int) -> String {
        let screens = NSScreen.screens
        let name = screens.indices.contains(index) ? screens[index].localizedName : "?"
        return L10n.groupScreenName(index, name)
    }
}

// MARK: - Group Name Field

/// Inline group-name editor that commits only a non-empty, trimmed name, and
/// only on Enter or focus loss — so clearing the field mid-edit can't persist an
/// empty name (which the store's sanitize would drop, silently deleting the group).
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

// MARK: - App Groups ViewModel

@MainActor
class AppGroupsViewModel: ObservableObject {
    @Published private(set) var groups: [AppGroup] = []

    private let settingsStore = UserDefaultsSwitcherSettingsStore()
    private var currentSettings = SwitcherSettings()

    init() { reload() }

    func reload() {
        currentSettings = settingsStore.load()
        groups = currentSettings.appGroups
    }

    func upsert(_ group: AppGroup) {
        if let index = currentSettings.appGroups.firstIndex(where: { $0.id == group.id }) {
            currentSettings.appGroups[index] = group
        } else {
            currentSettings.appGroups.append(group)
        }
        save()
    }

    /// Rename with a non-empty trimmed name (GroupNameField enforces this)
    func rename(_ group: AppGroup, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = currentSettings.appGroups.firstIndex(where: { $0.id == group.id }) else { return }
        currentSettings.appGroups[index].name = name
        save()
    }

    func delete(_ group: AppGroup) {
        currentSettings.appGroups.removeAll { $0.id == group.id }
        save()
    }

    private func save() {
        // Read-modify-write only the appGroups domain onto freshly persisted
        // settings, so a concurrent pinned-apps edit isn't clobbered.
        var persisted = settingsStore.load()
        persisted.appGroups = currentSettings.appGroups
        try? settingsStore.save(persisted)
        reload()
        NotificationCenter.default.post(name: .switcherSettingsDidChange, object: nil)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let switcherSettingsDidChange = Notification.Name("switcherSettingsDidChange")
}
