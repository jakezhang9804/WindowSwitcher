import SwiftUI
import AppKit
import KeyboardShortcuts
import AppSwitcherKit

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
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
        .frame(width: 600, height: 520)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show Switcher:", name: .showSwitcher)
            } header: {
                Text("Keyboard Shortcuts")
            }

            Section {
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
            } header: {
                Text("Startup")
            }

            Section {
                HStack(spacing: 10) {
                    TextField("Search apps by name or bundle identifier", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)

                    if viewModel.isLoadingApps {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Reset to Show All") {
                        viewModel.resetToShowAllApps()
                    }
                    .disabled(viewModel.isUsingDefaultVisibility)
                }

                if viewModel.isUsingDefaultVisibility {
                    Text("Whitelist is not configured yet. All applications are visible by default.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if viewModel.filteredApps.isEmpty {
                    Text("No installed applications matched your search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(viewModel.filteredApps, id: \.bundleID) { app in
                                ApplicationSettingRow(
                                    app: app,
                                    isAllowed: viewModel.isAppAllowed(app.bundleID),
                                    triggerKey: viewModel.triggerKey(for: app.bundleID),
                                    hasConflict: viewModel.conflictingBundleIDs.contains(app.bundleID),
                                    onAllowedChange: { isAllowed in
                                        viewModel.setAppAllowed(app.bundleID, isAllowed: isAllowed)
                                    },
                                    onTriggerKeyChange: { value in
                                        viewModel.updateTriggerKey(for: app.bundleID, rawInput: value)
                                    }
                                )
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 280)
                }

                if let validationMessage = viewModel.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Applications in Switcher")
            } footer: {
                Text("You can assign one single key (A-Z or 0-9) per app. The key is active only while the switcher panel is visible.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ApplicationSettingRow: View {
    let app: InstalledApp
    let isAllowed: Bool
    let triggerKey: String
    let hasConflict: Bool
    let onAllowedChange: (Bool) -> Void
    let onTriggerKeyChange: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isAllowed },
                    set: onAllowedChange
                )
            )
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            TextField(
                "A",
                text: Binding(
                    get: { triggerKey },
                    set: onTriggerKeyChange
                )
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 44)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hasConflict ? Color.red.opacity(0.15) : Color.primary.opacity(0.04))
        )
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
