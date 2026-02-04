import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show Switcher:", name: .showSwitcher)
            } header: {
                Text("Keyboard Shortcuts")
            }
            
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("windowWidth") private var windowWidth: Double = 600
    @AppStorage("maxResults") private var maxResults: Int = 20
    
    var body: some View {
        Form {
            Section {
                Slider(value: $windowWidth, in: 400...800, step: 50) {
                    Text("Window Width")
                } minimumValueLabel: {
                    Text("400")
                } maximumValueLabel: {
                    Text("800")
                }
                
                Stepper("Max Results: \(maxResults)", value: $maxResults, in: 10...50, step: 5)
            } header: {
                Text("Window")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("WindowSwitcher")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("A fast and native window switcher for macOS")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Check for Updates") {
                // Trigger Sparkle update check
            }
        }
        .padding()
    }
}
