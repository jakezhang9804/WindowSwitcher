import SwiftUI
import KeyboardShortcuts
import AppSwitcherKit

/// Settings window
/// 3 Tabs: Preferences, Hotkeys, About
struct SettingsView: View {
    var body: some View {
        TabView {
            PreferencesTab()
                .tabItem {
                    Label("Preferences", systemImage: "gearshape")
                }

            HotkeysTab()
                .tabItem {
                    Label("Hotkeys", systemImage: "command")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - Custom Section Style (replaces GroupBox for proper alignment)

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Preferences Tab

struct PreferencesTab: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("panelPosition") private var panelPosition = "center"
    @AppStorage("selectedScreenIndex") private var selectedScreenIndex = 0
    @AppStorage("appTheme") private var appTheme = "system"

    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var appConfigVM = AppConfigViewModel()

    @State private var isAccessibilityGranted = false
    @State private var isScreenRecordingGranted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Permissions
                SettingsSection("Permissions") {
                    Text("WindowSwitcher needs the following permissions to work properly:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    PermissionRow(
                        title: "Accessibility",
                        description: "Required to activate and raise windows",
                        isGranted: isAccessibilityGranted,
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    )

                    PermissionRow(
                        title: "Screen Recording",
                        description: "Required to read window titles for search and display",
                        isGranted: isScreenRecordingGranted,
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    )

                    Text("After granting permissions, you may need to restart the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onAppear { checkPermissions() }

                // General
                SettingsSection("General") {
                    Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    Toggle("Start at login", isOn: $settingsVM.launchAtLogin)
                }

                // Appearance
                SettingsSection("Appearance") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Theme")
                            .font(.subheadline.weight(.medium))
                        Picker("", selection: $appTheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Panel Position")
                            .font(.subheadline.weight(.medium))
                        Picker("", selection: $panelPosition) {
                            Text("Left").tag("left")
                            Text("Center").tag("center")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                }

                // Show on Screen
                SettingsSection("Show on Screen") {
                    Text("Choose which screen the switcher panel appears on.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedScreenIndex) {
                        ForEach(Array(screenNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)

                    Text("\(NSScreen.screens.count) screen\(NSScreen.screens.count == 1 ? "" : "s") detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Pinned Apps
                SettingsSection("Pinned Apps") {
                    Text("Select apps to pin. The switcher will only cycle through pinned apps. Optionally assign a trigger key (A-Z, 0-9) to quickly switch to a specific app via Option + Key.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Search installed apps...", text: $appConfigVM.searchText)
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    if appConfigVM.filteredApps.isEmpty {
                        Text("No apps found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(appConfigVM.filteredApps) { app in
                                    PinnedAppRow(app: app, viewModel: appConfigVM)
                                    Divider()
                                }
                            }
                        }
                        .frame(height: 240)
                    }

                    if let errorMsg = appConfigVM.errorMessage {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Screen Names

    private var screenNames: [String] {
        NSScreen.screens.enumerated().map { index, screen in
            screen.localizedName
        }
    }

    // MARK: - Permission Check

    private func checkPermissions() {
        // Check Accessibility: try AXIsProcessTrusted first, then functional test
        isAccessibilityGranted = checkAccessibilityPermission()

        // Check Screen Recording: try to get a window title via CGWindowList
        isScreenRecordingGranted = checkScreenRecordingPermission()
    }

    private func checkAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }

        // Functional test: try to query the system-wide element
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value)
        if result == .success { return true }

        // Try querying a running app's windows
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps.prefix(3) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var roleRef: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &roleRef)
            if roleResult == .success { return true }
        }

        return false
    }

    private func checkScreenRecordingPermission() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // If we can read at least one window title, permission is granted
        for window in windowList {
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return true
            }
        }
        return false
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isGranted ? .green : .red)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isGranted {
                Button("Open Settings", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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
                    Text("Option +")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("Key", text: $triggerKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: triggerKeyText) { _, newValue in
                            let filtered = String(newValue.prefix(1)).uppercased()
                            if filtered != newValue {
                                triggerKeyText = filtered
                            }
                            viewModel.setTriggerKey(app.bundleID, key: filtered)
                        }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear {
            triggerKeyText = viewModel.triggerKey(for: app.bundleID)
        }
    }
}

// MARK: - Hotkeys Tab

struct HotkeysTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show Switcher:", name: .showSwitcher)
            } header: {
                Text("Keyboard Shortcuts")
            }

            Section {
                Text("Press the shortcut key to quickly switch between windows.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("You can also assign per-app trigger keys in Preferences > Pinned Apps. Use Option + [Key] to switch directly to a specific app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Tips")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text("WindowSwitcher")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(currentVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A fast and native window switcher for macOS")
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
                Text("Checking for updates...")
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
                    Text("Version \(version) is available!")
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
                    Button("Download Update") {
                        updateService.openDownload()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip This Version") {
                        updateService.skipCurrentUpdate()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } else {
            Button("Check for Updates") {
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
            Text("Powered by")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Link("Manus", destination: URL(string: "https://manus.im")!)
                .font(.system(size: 11, weight: .semibold))
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
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let switcherSettingsDidChange = Notification.Name("switcherSettingsDidChange")
}
