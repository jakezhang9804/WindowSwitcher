import SwiftUI
import KeyboardShortcuts

/// 设置窗口，参考 TabTab 的 Preferences 设计
/// 4 个 Tab：Preferences, Hotkeys, License(去掉), About
/// 简化为：Preferences, Hotkeys, About
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
        .frame(width: 520, height: 480)
    }
}

// MARK: - Preferences Tab

struct PreferencesTab: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("windowOnlyMode") private var windowOnlyMode = false
    @StateObject private var appConfigVM = AppConfigViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Section
                GroupBox(label: Text("General").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                        Toggle("Start at login", isOn: $startAtLogin)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Switcher Settings Section
                GroupBox(label: Text("Switcher Settings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Window only mode", isOn: $windowOnlyMode)
                        Text("When enabled, individual tabs of each app window will no longer be tracked.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // App Specific Configurations
                GroupBox(label: Text("App specific configurations").font(.headline)) {
                    VStack(spacing: 0) {
                        // Search field
                        TextField("Search Apps", text: $appConfigVM.searchText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 8)
                        
                        Divider()
                        
                        // App list
                        if appConfigVM.filteredApps.isEmpty {
                            Text("No running apps found")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(appConfigVM.filteredApps) { app in
                                        AppConfigRow(app: app, viewModel: appConfigVM)
                                        Divider()
                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - App Config Row

struct AppConfigRow: View {
    let app: AppConfigItem
    @ObservedObject var viewModel: AppConfigViewModel
    
    var body: some View {
        HStack(spacing: 10) {
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
            
            // Ignore app toggle
            Toggle("Ignore app", isOn: Binding(
                get: { viewModel.isIgnored(app.bundleID) },
                set: { viewModel.setIgnored(app.bundleID, ignored: $0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

// MARK: - App Config ViewModel

struct AppConfigItem: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let icon: NSImage?
    
    init(from app: NSRunningApplication) {
        self.id = app.bundleIdentifier ?? "\(app.processIdentifier)"
        self.name = app.localizedName ?? "Unknown"
        self.bundleID = app.bundleIdentifier ?? ""
        self.icon = app.icon
    }
}

@MainActor
class AppConfigViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var apps: [AppConfigItem] = []
    @AppStorage("ignoredApps") private var ignoredAppsData: Data = Data()
    
    private var ignoredApps: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: ignoredAppsData)) ?? []
        }
        set {
            ignoredAppsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    var filteredApps: [AppConfigItem] {
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    init() {
        loadRunningApps()
    }
    
    func loadRunningApps() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { AppConfigItem(from: $0) }
        apps = runningApps
    }
    
    func isIgnored(_ bundleID: String) -> Bool {
        ignoredApps.contains(bundleID)
    }
    
    func setIgnored(_ bundleID: String, ignored: Bool) {
        if ignored {
            ignoredApps.insert(bundleID)
        } else {
            ignoredApps.remove(bundleID)
        }
    }
}
