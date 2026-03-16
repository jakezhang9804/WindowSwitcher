import SwiftUI
import ServiceManagement

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var launchAtLogin: Bool = false {
        didSet { updateLaunchAtLogin() }
    }

    init() {
        loadSettings()
    }

    private func loadSettings() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
                print("Failed to update launch at login: \(error)")
            }
        }
    }
}
