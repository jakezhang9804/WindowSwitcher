import SwiftUI
import ServiceManagement
import AppSwitcherKit

@MainActor
class SettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != oldValue else {
                return
            }
            updateLaunchAtLogin()
        }
    }

    @Published var searchText: String = ""
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var settings: SwitcherSettings = .init()
    @Published private(set) var conflictingBundleIDs: Set<String> = []
    @Published private(set) var validationMessage: String?
    @Published private(set) var isLoadingApps: Bool = false

    // MARK: - Dependencies

    private let appCatalog: any AppCatalogProviding
    private let settingsStore: any SwitcherSettingsStoring

    // MARK: - Initialization

    init(
        appCatalog: any AppCatalogProviding = InstalledAppCatalog(),
        settingsStore: any SwitcherSettingsStoring = UserDefaultsSwitcherSettingsStore()
    ) {
        self.appCatalog = appCatalog
        self.settingsStore = settingsStore

        loadSettings()
        loadInstalledApps()
    }

    // MARK: - Computed Properties

    var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return installedApps
        }

        let lowercasedQuery = query.lowercased()
        return installedApps.filter { app in
            app.displayName.lowercased().contains(lowercasedQuery) ||
            app.bundleID.lowercased().contains(lowercasedQuery)
        }
    }

    var isUsingDefaultVisibility: Bool {
        settings.allowedBundleIDs.isEmpty
    }

    // MARK: - App Visibility

    func isAppAllowed(_ bundleID: String) -> Bool {
        if settings.allowedBundleIDs.isEmpty {
            return true
        }
        return settings.allowedBundleIDs.contains(bundleID)
    }

    func setAppAllowed(_ bundleID: String, isAllowed: Bool) {
        validationMessage = nil

        var nextSettings = settings

        if nextSettings.allowedBundleIDs.isEmpty {
            guard !isAllowed else {
                return
            }

            let allBundleIDs = Set(installedApps.map(\.bundleID))
            nextSettings.allowedBundleIDs = allBundleIDs.subtracting([bundleID])
            persist(nextSettings)
            return
        }

        if isAllowed {
            nextSettings.allowedBundleIDs.insert(bundleID)
        } else {
            nextSettings.allowedBundleIDs.remove(bundleID)

            if nextSettings.allowedBundleIDs.isEmpty {
                validationMessage = "At least one app must remain in whitelist, or use Reset to Show All."
                return
            }
        }

        persist(nextSettings)
    }

    func resetToShowAllApps() {
        validationMessage = nil
        var nextSettings = settings
        nextSettings.allowedBundleIDs = []
        persist(nextSettings)
    }

    // MARK: - App Trigger Keys

    func triggerKey(for bundleID: String) -> String {
        settings.triggerKey(for: bundleID) ?? ""
    }

    func updateTriggerKey(for bundleID: String, rawInput: String) {
        validationMessage = nil
        conflictingBundleIDs = []

        var nextBindings = settings.appBindings.filter { $0.bundleID != bundleID }

        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            var nextSettings = settings
            nextSettings.appBindings = nextBindings
            persist(nextSettings)
            return
        }

        guard let normalizedKey = AppBindingRules.normalizeTriggerKey(trimmed) else {
            validationMessage = "Only A-Z and 0-9 single-key triggers are supported."
            return
        }

        let candidateBinding = AppBinding(bundleID: bundleID, triggerKey: normalizedKey)
        nextBindings.append(candidateBinding)

        let conflicts = AppBindingRules.conflictingBundleIDs(for: nextBindings)
        if !conflicts.isEmpty {
            conflictingBundleIDs = conflicts

            if let conflictingBundleID = conflicts.first(where: { $0 != bundleID }),
               let app = installedApps.first(where: { $0.bundleID == conflictingBundleID }) {
                validationMessage = "Key \(normalizedKey) is already used by \(app.displayName)."
            } else {
                validationMessage = "Key \(normalizedKey) conflicts with another app binding."
            }

            return
        }

        nextBindings = AppBindingRules.normalizedBindings(nextBindings)

        var nextSettings = settings
        nextSettings.appBindings = nextBindings
        persist(nextSettings)
    }

    // MARK: - Private Methods

    private func loadSettings() {
        settings = settingsStore.load()
        settings.appBindings = AppBindingRules.normalizedBindings(settings.appBindings)

        if !settings.appBindings.isEmpty {
            persist(settings)
        }

        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func loadInstalledApps() {
        isLoadingApps = true
        installedApps = appCatalog.fetchInstalledApps()
        isLoadingApps = false
    }

    private func persist(_ nextSettings: SwitcherSettings) {
        do {
            try settingsStore.save(nextSettings)
            settings = settingsStore.load()
            conflictingBundleIDs = []
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                validationMessage = "Failed to update launch at login: \(error.localizedDescription)"
            }
        }
    }
}
