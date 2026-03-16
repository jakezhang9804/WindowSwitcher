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

// MARK: - Preferences Tab

struct PreferencesTab: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var appConfigVM = AppConfigViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Section
                GroupBox(label: Text("General").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                        Toggle("Start at login", isOn: $settingsVM.launchAtLogin)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Pinned Apps Section
                GroupBox(label: Text("Pinned Apps").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select apps to pin. The switcher will only cycle through pinned apps. Optionally assign a trigger key (A-Z, 0-9) to quickly switch to a specific app via Option + Key.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        // Search field
                        TextField("Search installed apps...", text: $appConfigVM.searchText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 4)

                        Divider()

                        // App list
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

                        // Error message
                        if let errorMsg = appConfigVM.errorMessage {
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
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
            // Pin toggle
            Toggle("", isOn: Binding(
                get: { viewModel.isPinned(app.bundleID) },
                set: { viewModel.setPinned(app.bundleID, pinned: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app")
                    .frame(width: 22, height: 22)
            }

            // App name
            Text(app.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            // Trigger key input (only shown when pinned)
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
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text("WindowSwitcher")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A fast and native window switcher for macOS")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
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

        // Also add currently running apps that might not be in /Applications
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
            // Also remove any trigger key binding
            currentSettings.appBindings.removeAll { $0.bundleID == bundleID }
        }
        saveSettings()
    }

    func triggerKey(for bundleID: String) -> String {
        currentSettings.triggerKey(for: bundleID) ?? ""
    }

    func setTriggerKey(_ bundleID: String, key: String) {
        // Remove existing binding for this bundle
        currentSettings.appBindings.removeAll { $0.bundleID == bundleID }

        // Add new binding if key is not empty
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
            // Reload to get normalized version
            currentSettings = settingsStore.load()
            // Post notification so other parts of the app can react
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
