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

            // Pinned Apps — bounded inner list like System Settings' Login Items
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("", text: $appConfigVM.searchText, prompt: Text(L10n.searchAppsPlaceholder))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                }

                if let errorMsg = appConfigVM.errorMessage {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if appConfigVM.filteredApps.isEmpty {
                    Text(L10n.noAppsFound)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    List {
                        ForEach(appConfigVM.filteredApps) { app in
                            PinnedAppRow(app: app, viewModel: appConfigVM)
                        }
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds(.enabled)
                    .environment(\.defaultMinListRowHeight, 30)
                    .frame(height: 260)
                }
            } header: {
                Text(L10n.pinnedAppsTitle)
            } footer: {
                Text(L10n.pinnedAppsDescription)
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

// MARK: - Pinned App Row

struct PinnedAppRow: View {
    let app: AppDisplayItem
    @ObservedObject var viewModel: AppConfigViewModel

    @State private var triggerKeyText: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { viewModel.isPinned(app.bundleID) },
                set: { viewModel.setPinned(app.bundleID, pinned: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app")
                    .frame(width: 22, height: 22)
            }

            Text(app.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            if viewModel.isPinned(app.bundleID) {
                HStack(spacing: 4) {
                    Text("⌥ +")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    // In a Form the title parameter renders as a separate label
                    // and wrecks the row layout — hide it and center the key
                    TextField("", text: $triggerKeyText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 36)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: triggerKeyText) { _, newValue in
                            let filtered = String(newValue.prefix(1)).uppercased()
                            guard filtered == newValue else {
                                // Re-triggers onChange with the normalized value,
                                // so the save happens exactly once
                                triggerKeyText = filtered
                                return
                            }
                            viewModel.setTriggerKey(app.bundleID, key: filtered)
                            if viewModel.errorMessage != nil {
                                // Save rejected (duplicate key) — show the stored value
                                triggerKeyText = viewModel.triggerKey(for: app.bundleID)
                            }
                        }
                }
            }
        }
        .onAppear {
            triggerKeyText = viewModel.triggerKey(for: app.bundleID)
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

@MainActor
class AppConfigViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var apps: [AppDisplayItem] = []
    @Published var errorMessage: String?

    private let settingsStore: UserDefaultsSwitcherSettingsStore
    private let catalog: InstalledAppCatalog
    private var currentSettings: SwitcherSettings

    var filteredApps: [AppDisplayItem] {
        let sorted = apps.sorted { a, b in
            let aPinned = isPinned(a.bundleID)
            let bPinned = isPinned(b.bundleID)
            if aPinned != bPinned { return aPinned }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    init() {
        self.settingsStore = UserDefaultsSwitcherSettingsStore()
        self.catalog = InstalledAppCatalog()
        self.currentSettings = SwitcherSettings()
        loadSettings()
        loadApps()
    }

    private func loadSettings() {
        currentSettings = settingsStore.load()
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

    func isPinned(_ bundleID: String) -> Bool {
        currentSettings.allowedBundleIDs.contains(bundleID)
    }

    func setPinned(_ bundleID: String, pinned: Bool) {
        if pinned {
            currentSettings.allowedBundleIDs.insert(bundleID)
        } else {
            currentSettings.allowedBundleIDs.remove(bundleID)
            currentSettings.appBindings.removeAll { $0.bundleID == bundleID }
        }
        saveSettings()
    }

    func triggerKey(for bundleID: String) -> String {
        currentSettings.triggerKey(for: bundleID) ?? ""
    }

    func setTriggerKey(_ bundleID: String, key: String) {
        currentSettings.appBindings.removeAll { $0.bundleID == bundleID }

        if !key.isEmpty {
            currentSettings.appBindings.append(
                AppBinding(bundleID: bundleID, triggerKey: key)
            )
        }
        saveSettings()
    }

    private func saveSettings() {
        errorMessage = nil
        do {
            try settingsStore.save(currentSettings)
            currentSettings = settingsStore.load()
            NotificationCenter.default.post(name: .switcherSettingsDidChange, object: nil)
        } catch {
            // Roll back the in-memory settings — keeping the rejected change
            // around would make every subsequent save fail as well
            currentSettings = settingsStore.load()
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let switcherSettingsDidChange = Notification.Name("switcherSettingsDidChange")
}
